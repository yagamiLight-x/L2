open Core.Std

type id = string with compare, sexp

module Ctx = struct
  module StringMap = Map.Make(String)
  type 'a t = 'a StringMap.t ref
  exception UnboundError of id

  (** Return an empty context. *)
  let empty () : 'a t = ref StringMap.empty

  (** Look up an id in a context. *)
  let lookup ctx id = StringMap.find !ctx id
  let lookup_exn ctx id = match lookup ctx id with
    | Some v -> v
    | None -> raise (UnboundError id)

  (** Bind a type or value to an id, returning a new context. *)
  let bind ctx id data = ref (StringMap.add !ctx ~key:id ~data:data)
  let bind_alist ctx alist = 
    List.fold alist ~init:ctx ~f:(fun ctx' (id, data) -> bind ctx' id data)

  (** Remove a binding from a context, returning a new context. *)
  let unbind ctx id = ref (StringMap.remove !ctx id)

  (** Bind a type or value to an id, updating the context in place. *)
  let update ctx id data = ctx := StringMap.add !ctx ~key:id ~data:data

  (** Remove a binding from a context, updating the context in place. *)
  let remove ctx id = ctx := StringMap.remove !ctx id

  let merge c1 c2 ~f:f = ref (StringMap.merge !c1 !c2 ~f:f)
  let map ctx ~f:f = ref (StringMap.map !ctx ~f:f)
  let filter ctx ~f:f = ref (StringMap.filter !ctx ~f:f)
  let filter_mapi ctx ~f:f = ref (StringMap.filter_mapi !ctx ~f:f)

  let keys ctx = StringMap.keys !ctx

  let of_alist alist = ref (StringMap.of_alist alist)
  let of_alist_exn alist = ref (StringMap.of_alist_exn alist)
  let to_alist ctx = StringMap.to_alist !ctx
  let to_string ctx (str: 'a -> string) =
    to_alist ctx 
    |> List.map ~f:(fun (key, value) -> key ^ ": " ^ (str value))
    |> String.concat ~sep:", "
    |> fun s -> "{ " ^ s ^ " }"
end

(** Represents the type of a value or expression. *)
type typ =
  | Const_t of const_typ
  | App_t of id * typ list
  | Arrow_t of typ list * typ
  | Var_t of var_typ
and const_typ = Num | Bool

(** Type variables can be either free or quantified. A type scheme
cannot contain free type variables. *)
and var_typ =
  | Free of int
  | Quant of string
  with compare, sexp

(** Module to manage built in operators and their metadata. *)
module Op = struct
  type t =
    | Plus
    | Minus
    | Mul
    | Div
    | Mod
    | Eq
    | Neq
    | Lt
    | Leq
    | Gt
    | Geq
    | And
    | Or
    | Not
    | Cons
    | Car
    | Cdr
    | If with compare, sexp

  (** Type for storing operator metadata. *)
  type metadata = {
    typ    : typ;
    commut : bool;
    assoc  : bool;
    str    : string;
  }

  let metadata_by_op = [
    Plus,  { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Num);
             commut = true;  assoc = true;  str = "+"; };
    Minus, { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Num);
             commut = false; assoc = false; str = "-"; };
    Mul,   { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Num);
             commut = true;  assoc = true;  str = "*"; };
    Div,   { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Num);
             commut = false; assoc = false; str = "/"; };
    Mod,   { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Num);
             commut = false; assoc = false; str = "%"; };
    Eq,    { typ = Arrow_t ([Var_t (Quant "a"); Var_t (Quant "a")], Const_t Bool);
             commut = true;  assoc = false; str = "="; };
    Neq,   { typ = Arrow_t ([Var_t (Quant "a"); Var_t (Quant "a")], Const_t Bool);
             commut = true;  assoc = false; str = "!="; };
    Lt,    { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Bool);
             commut = false; assoc = false; str = "<"; };
    Leq,   { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Bool);
             commut = false; assoc = false; str = "<="; };
    Gt,    { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Bool);
             commut = false; assoc = false; str = ">"; };
    Geq,   { typ = Arrow_t ([Const_t Num; Const_t Num], Const_t Bool);
             commut = false; assoc = false; str = ">="; };
    And,   { typ = Arrow_t ([Const_t Bool; Const_t Bool], Const_t Bool);
             commut = true;  assoc = true;  str = "&"; };
    Or,    { typ = Arrow_t ([Const_t Bool; Const_t Bool], Const_t Bool);
             commut = true;  assoc = true;  str = "|"; };
    Not,   { typ = Arrow_t ([Const_t Bool], Const_t Bool);
             commut = false; assoc = false; str = "~"; };
    Cons,  { typ = Arrow_t ([Var_t (Quant "a"); App_t ("list", [Var_t (Quant "a")])], 
                            App_t ("list", [Var_t (Quant "a")]));
             commut = false; assoc = false; str = "cons"; };
    Car,   { typ = Arrow_t ([App_t ("list", [Var_t (Quant "a")])], Var_t (Quant "a"));
             commut = false; assoc = false; str = "car"; };
    Cdr,   { typ = Arrow_t ([App_t ("list", [Var_t (Quant "a")])], 
                            App_t ("list", [Var_t (Quant "a")]));
             commut = false; assoc = false; str = "cdr"; };
    If,    { typ = Arrow_t ([Const_t Bool; Var_t (Quant "a"); Var_t (Quant "a")], 
                            Var_t (Quant "a"));
             commut = false; assoc = false; str = "if"; };
  ]

  let op_by_str = metadata_by_op
                  |> List.map ~f:(fun (op, meta) -> meta.str, op)
                  |> String.Map.of_alist_exn

  (** Get operator record from operator. *)
  let meta op = 
    let (_, meta) = List.find_exn metadata_by_op ~f:(fun (op', _) -> op = op') in
    meta

  let typ op = (meta op).typ
  let arity op = match (meta op).typ with
    | Arrow_t (args, _) -> List.length args
    | _ -> raise Not_found
  let assoc op = (meta op).assoc
  let commut op = (meta op).commut

  let to_string op = (meta op).str
  let of_string str = String.Map.find_exn op_by_str str
end

(** Represents identifiers and typed identifiers. *)
type typed_id = id * typ with compare, sexp

(** Types for expressions and values. *)
type expr = 
  [ `Num of int
  | `Bool of bool
  | `List of expr list
  | `Id of id
  | `Let of id * expr * expr
  | `Lambda of id list * expr
  | `Apply of expr * (expr list)
  | `Op of Op.t * (expr list)
  ] with compare, sexp

type typed_expr =
  [ `Num of int * typ
  | `Bool of bool * typ
  | `List of expr list * typ
  | `Id of id * typ
  | `Let of id * expr * expr * typ
  | `Lambda of id list * expr * typ
  | `Apply of expr * (expr list) * typ
  | `Op of Op.t * (expr list) * typ
  ] with compare, sexp

type example = expr * expr with compare, sexp

type function_def = [ `Define of id * [ `Lambda of typed_id list * typ * expr ] ]

type constr = expr * (id list)

type typed_expr = expr * typ with compare, sexp

type type_pred = typ list -> typ -> bool

(** Calculate the size of an expression. *)
let rec size (e: expr) : int =
  let sum_sizes = List.fold_left ~init:0 ~f:(fun acc e -> acc + size e) in
  match e with
  | `Id _
  | `Num _
  | `Bool _ -> 1
  | `Op (_, args) -> 1 + sum_sizes args
  | `List l -> 1 + (List.fold l ~init:0 ~f:(fun acc c -> acc + size (c :> expr)))
  | `Let (_, a, b) -> 1 + size a + size b
  | `Lambda (args, body) -> 1 + (List.length args) + size body
  | `Apply (a, l) -> 1 + size a + sum_sizes l

(** Create an S-expression from the provided string list and brackets. *)
let sexp lb strs rb = lb ^ (String.concat ~sep:" " strs) ^ rb

(** Convert a type to a string. *)
let rec typ_to_string typ =
  let tlist_str typs =
    typs |> List.map ~f:typ_to_string |> String.concat ~sep:", "
  in
  match typ with
  | Const_t Num -> "num"
  | Const_t Bool -> "bool"
  | Var_t (Free id) -> "ft" ^ (Int.to_string id)
  | Var_t (Quant name) -> name
  | App_t (id, args) -> 
     Printf.sprintf "%s[%s]" id (tlist_str args)
  | Arrow_t ([arg], ret) -> 
     Printf.sprintf "(%s -> %s)" (typ_to_string arg) (typ_to_string ret)
  | Arrow_t (args, ret) -> 
     Printf.sprintf "((%s) -> %s)" (tlist_str args) (typ_to_string ret)

(** Convert and expression to a string. *)
let rec expr_to_string (expr: expr) : string =
  let str_all l = List.map ~f:expr_to_string l in
  match expr with
  | `Num x  -> Int.to_string x
  | `Bool true -> "#t"
  | `Bool false -> "#f"
  | `List x -> sexp "[" (List.map ~f:expr_to_string x) "]"
  | `Id x -> x
  | `Op (op, args) -> sexp "(" ((Op.to_string op)::(str_all args)) ")"
  | `Let (x, y, z) -> sexp "(" ["let"; x; expr_to_string y; expr_to_string z] ")"
  | `Apply (x, y)  -> sexp "(" ((expr_to_string x)::(str_all y)) ")"
  | `Lambda (args, body) -> sexp "(" ["lambda"; sexp "(" args ")"; expr_to_string body] ")"

let example_to_string (ex: example) : string =
  let e1, e2 = ex in
  (expr_to_string e1) ^ " -> " ^ (expr_to_string e2)
