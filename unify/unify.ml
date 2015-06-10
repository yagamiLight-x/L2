type id = string

exception Non_unifiable
exception Translation_error
exception Unknown

type term =
  | Var of id
  | Term of id * term list

type sterm =
  | Cons of sterm * sterm
  | K of id (* Konstant *)
  | V of id (* Variable *)
  | U of id * bool (* Volatile? variable *)

type substitution = (id * term) list

(* the occurs check *)
let rec occurs (x : id) (t : term) : bool =
  match t with
  | Var y -> x = y
  | Term (_, s) -> List.exists (occurs x) s

(* substitute term s for all occurrences of variable x in term t *)
let rec subst (s : term) (x : id) (t : term) : term =
  match t with
  | Var y -> if x = y then s else t
  | Term (f, u) -> Term (f, List.map (subst s x) u)

(* apply a substitution right to left *)
let apply (s : substitution) (t : term) : term =
  List.fold_right (fun (x, u) -> subst u x) s t

(* unify one pair *)
let rec unify_one (s : term) (t : term) : substitution =
  match (s, t) with
  | (Var x, Var y) -> if x = y then [] else [(x, t)]
  | (Term (f, sc), Term (g, tc)) ->
      if f = g && List.length sc = List.length tc
      then unify (List.combine sc tc)
      else raise Non_unifiable
  | ((Var x, (Term (_, _) as t)) | ((Term (_, _) as t), Var x)) ->
      if occurs x t
      then raise Non_unifiable
      else [(x, t)]

(* unify a list of pairs *)
and unify (s : (term * term) list) : substitution =
  match s with
  | [] -> []
  | (x, y) :: t ->
      let t2 = unify t in
      let t1 = unify_one (apply t2 x) (apply t2 y) in
      t1 @ t2

let fvar = ref 0

let fresh () : string =
  fvar := !fvar + 1; "V" ^ string_of_int !fvar

(* Support code *)
let rec translate (s: sterm) : term =
  match s with
  | Cons(x, y) -> 
      let t1 = translate x and t2 = translate y in
      Term("Cons", [t1] @ [t2])
  | K(c) -> Term(c, [])
  | V(c) | U(c, _) -> Var(c)

let rec retranslate (t: term) : sterm =
  match t with
  | Var(v) -> V(v)
  | Term(k, []) -> K(k)
  | Term("Cons", h::t) ->
    (match t with
    | tt::[] -> Cons(retranslate h, retranslate tt)
    | _ -> raise Translation_error)
  | _ -> raise Translation_error

let rec to_string (s: sterm) : string =
  match s with
  | Cons(h, t) -> "Cons(" ^ (to_string h) ^ "," ^ (to_string t) ^ ")"
  | K(t) | V(t) -> t
  | U(t, vol) -> if vol then raise Unknown (* sanity check *) else t

and print_sub (s: substitution) = 
  let ss = List.map (fun (i, t) -> i ^ " = " ^ (to_string (retranslate t))) s
  in List.iter (fun t -> Printf.printf "%s\n" t) ss
(* End Support code *)

(* "concretize" one volatile term with the one from hypothesis *)
let rec make_one_concrete (s1: sterm) (s3: sterm) (made: bool) =
  if made then made, s3 else
  match s1, s3 with
  | Cons(h1, t1), Cons(h2, t2) ->
      let md1, sh = make_one_concrete h1 h2 made in
      let md2, st = make_one_concrete t1 t2 md1 in
      md2, Cons(sh, st)
  | K(_), K(_) | V(_), V(_) | _, U(_, false) -> false, s3
  | K(_), U(_, true) | V(_), U(_, true) -> true, s1
  | Cons(_, _), U(_, true) -> true, Cons(U(fresh (), true), U(fresh (), true))
  | _,_ -> raise Unknown

(* the non-volatile term is now part of the core *)
let rec make_one_non_volatile (s3: sterm) =
  let rec aux (ss: sterm) (made: bool) =
    if made then made, ss else
    match ss with
    | Cons(h, t) ->
      let md1, sh = aux h made in
      let md2, st = aux t md1 in
      md2, Cons(sh, st)
    | K(_) | V(_) | U(_, false) -> false, ss
    | U(u, true) -> true, U("C" ^ u, false)
  in let _, ss3 = aux s3 false in ss3

(* concretize <-> unify loop until we cannot concretize anymore *)
let rec unifiable_core_aux (s1: sterm) (s3: sterm) (s2: sterm) =
  try
    let made, s3' = make_one_concrete s1 s3 false in
    let sub = unify [translate s3', translate s2] in
    if not made then s3', sub else unifiable_core_aux s1 s3' s2
  with Non_unifiable -> unifiable_core_aux s1 (make_one_non_volatile s3) s2

(* Main *)
let unifiable_core (s1: sterm) (s2: sterm) =
  try 
    let sub = unify [translate s1, translate s2] in s1, sub
  with Non_unifiable -> unifiable_core_aux s1 (U(fresh (), true)) s2

;;

begin
  let term1 = Cons(K("1"), Cons(K("2"), K("[]")))
  and term2 = Cons(K("7"), Cons(K("2"), Cons(K("3"), K("[]")))) in
  (*let term1 = Cons(K("1"), Cons(K("2"), K("[]")))
  and term2 = Cons(K("3"), Cons(K("4"), K("[]"))) in*)
  let core, sub = unifiable_core term1 term2 in
  Printf.printf "%s\n" (to_string core);
  print_sub sub;
end;