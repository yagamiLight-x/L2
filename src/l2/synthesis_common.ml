open Core.Std

open Hypothesis
open Infer

module Generalizer = struct
  type t = Hole.t -> Specification.t -> (Hypothesis.t * Unifier.t) list
  
  let generalize_all generalize hypo =
    let open Hypothesis in
    List.fold_left
      (List.sort ~cmp:(fun (h1, _) (h2, _) -> Hole.compare h1 h2) (holes hypo))
      ~init:[ hypo ]
      ~f:(fun hypos (hole, spec) ->
          let children = List.filter (generalize hole spec) ~f:(fun (c, _) ->
              kind c = Abstract || Specification.verify spec (skeleton c))
          in
          List.map hypos ~f:(fun p -> List.map children ~f:(fun (c, u) ->
              apply_unifier (fill_hole hole ~parent:p ~child:c) u))
          |> List.concat)
end


(** Maps (hole, spec) pairs to the hypotheses that can fill in the hole and match the spec.

    The memoizer can be queried with a hole, a spec and a cost.

    Internally, the type of the hole and the types in the type context
    of the hole are normalized by substituting their free type
    variable ids with fresh ones. The memoizer only stores the
    normalized holes. This increases potential for sharing when
    different holes have the same type structure but different ids in
    their free type variables.
*)
module Memoizer = struct
  module type S = sig
    type t
    val create : unit -> t
    val get : t -> Hole.t -> Specification.t -> cost:int -> (Hypothesis.t * Unifier.t) list
  end

  let denormalize_unifier u map =
    Unifier.to_alist u
    |> List.filter_map ~f:(fun (k, v) -> Option.map (Int.Map.find map k) ~f:(fun k' -> k', v))
    |> Unifier.of_alist_exn

  module Key = struct
    module Hole_without_id = struct
      type t = {
        ctx : Type.t StaticDistance.Map.t;
        type_ : Type.t;
        symbol : Symbol.t;
      } [@@deriving compare, sexp]

      let normalize_free ctx t =
        let open Type in
        let fresh_int = Util.Fresh.mk_fresh_int_fun () in
        let rec norm t = match t with
          | Var_t { contents = Quant _ }
          | Const_t _ -> t
          | App_t (name, args) -> App_t (name, List.map args ~f:norm)
          | Arrow_t (args, ret) -> Arrow_t (List.map args ~f:norm, norm ret)
          | Var_t { contents = Free (id, level) } ->
            (match Int.Map.find !ctx id with
             | Some id -> Type.free id level
             | None ->
               let new_id = fresh_int () in
               ctx := Int.Map.add !ctx ~key:new_id ~data:id;
               Type.free new_id level)
          | Var_t { contents = Link t } -> norm t
        in
        norm t

      let of_hole h =
        let free_ctx = ref Int.Map.empty in
        let type_ = normalize_free free_ctx h.Hole.type_ in
        let type_ctx = StaticDistance.Map.map h.Hole.ctx ~f:(normalize_free free_ctx) in
        ({ ctx = type_ctx; symbol = h.Hole.symbol; type_; }, !free_ctx)
    end

    type t = {
      hole : Hole_without_id.t;
      spec : Specification.t;
    } [@@deriving compare, sexp]

    let hash = Hashtbl.hash

    let of_hole_spec hole spec =
      let (hole, map) = Hole_without_id.of_hole hole in
      ({ hole; spec; }, map)
  end

  module HoleTable = Hashtbl.Make(Key)
  module CostTable = Int.Table

  module HoleState = struct
    type t = {
      hypotheses : (Hypothesis.t * Unifier.t) list CostTable.t;
      generalizations : (Hypothesis.t * Unifier.t) list Lazy.t;
    } [@@deriving sexp]
  end

  type t = {
    hole_table : HoleState.t HoleTable.t;
    generalize : Generalizer.t;
  }

  let create g = {
    generalize = g;
    hole_table = HoleTable.create ();
  }

  (** Requires: 'm' is a memoization table. 'hypo' is a
      hypothesis. 'cost' is an integer cost.

      Ensures: Returns a list of hypotheses which are children of
      'hypo' and have cost 'cost'. Uses the memoization table to avoid
      as much computation as possible.  
  *)
  let rec fill_holes_in_hypothesis m hypo cost =
    let module H = Hypothesis in

    match H.kind hypo with
    | H.Concrete -> if H.cost hypo = cost then [ (hypo, Unifier.empty) ] else []
    | H.Abstract -> if H.cost hypo >= cost then [] else
        let holes = H.holes hypo in
        
        (* Determine all possible ways to fill in the holes in this generalization. *)
        let all_hole_costs =
          let num_holes = List.length holes in
          Util.m_partition (cost - H.cost hypo) num_holes
          |> List.concat_map ~f:Util.permutations
        in

        (* For each list of hole costs... *)
        List.concat_map all_hole_costs ~f:(fun hole_costs ->
            (* Fold over the holes and their corresponding cost... *)
            List.fold2_exn holes hole_costs ~init:[ (hypo, Unifier.empty) ]
              ~f:(fun hs (hole, spec) hole_cost ->
                  (* And select all hypotheses which could be used to fill them. *)
                  List.concat_map hs ~f:(fun (p, p_u) ->
                      let children = get m hole spec ~cost:hole_cost in

                      (* Fill in the hole and merge the unifiers. *)
                      List.map children ~f:(fun (c, c_u) ->
                          let u = Unifier.compose c_u p_u in
                          let h = H.fill_hole hole ~parent:p ~child:c in
                          h, u))))

        (* Only return concrete hypotheses which match the specification. *)
        |> List.filter ~f:(fun (h, _) -> match H.kind h with
            | H.Concrete -> H.verify h
            | H.Abstract -> failwiths "BUG: Did not fill in all holes." h H.sexp_of_t)

  and get m hole spec ~cost =
    if cost < 0 then raise (Invalid_argument "Argument out of range.") else
    if cost = 0 then [] else
      let module S = HoleState in
      let module H = Hypothesis in

      (* For the given hole and specification, select the 'state'
         object, which contains previously generated hypotheses for this
         hole, spec pair and possible generalizations of the hole. *)
      let (key, map) = Key.of_hole_spec hole spec in
      let state = HoleTable.find_or_add m.hole_table key ~default:(fun () ->
          {
            S.hypotheses = CostTable.create ();
            S.generalizations = Lazy.from_fun (fun () -> m.generalize hole spec);
          })
      in
      let ret =
        match CostTable.find state.S.hypotheses cost with
        (* If we have previously generated the hypotheses of this cost, return them. *)
        | Some hs -> hs

        (* Otherwise, we will need to use the available
           generalizations to generate hypothesis of the current cost. *)
        | None ->
          let hs =
          (* For each possible generalization, fill in its holes so
             that the resulting hypothesis has the correct cost. *)
            List.concat_map (Lazy.force state.S.generalizations) ~f:(fun (p, p_u) ->
              List.map (fill_holes_in_hypothesis m p cost) ~f:(fun (filled_p, filled_u) ->
                    (filled_p, Unifier.compose filled_u p_u)))
          in

          (* Save the computed result, so we can use it later. *)
          CostTable.add_exn state.S.hypotheses ~key:cost ~data:hs; hs
      in
      List.map ret ~f:(fun (h, u) -> (h, denormalize_unifier u map))
end