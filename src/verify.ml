open Core.Std
open Ast
open Eval
open Infer

exception VerifyError of string

let verify_error str = raise @@ VerifyError str

type status = 
  | Invalid
  | Valid
  | Error

type typed_constr = typed_expr * typed_id list

(* let typed_constr constr = *)
(*   let body, vars = constr in *)
(*   let body' = *)
(*     let typ_ctx = List.map vars ~f:(fun var -> (var, fresh_free 0)) |> Ctx.of_alist_exn in *)
(*     Infer.infer typ_ctx body in *)
(*   let ctx = Ctx.empty () in *)
(*   let rec find_vars texpr = match texpr with *)
(*     | Num _ | Bool _ -> () *)
(*     | List (x, _) -> List.iter x ~f:find_vars *)
(*     | Lambda ((_, x), _) -> find_vars x *)
(*     | Apply ((x, y), _) -> find_vars x; List.iter y ~f:find_vars *)
(*     | Op ((_, x), _) -> List.iter x ~f:find_vars *)
(*     | Let ((_, x, y), _) -> find_vars x; find_vars y; *)
(*     | Id (name, typ) -> if List.mem vars name then Ctx.update ctx name typ else () *)
(*   in *)
(*   find_vars body'; *)
(*   let vars' = List.map vars ~f:(fun var ->  *)
(*                                 match Ctx.lookup ctx var with *)
(*                                 | Some typ -> var, typ *)
(*                                 | None -> verify_error "Could not find type for constraint var.") in *)
(*   body', vars' *)

(* let rec expand ctx expr = *)
(*   let exp e = expand ctx e in *)
(*   let exp_all es = List.map ~f:exp es in *)
(*   match expr with *)
(*   | `Id name -> (match Ctx.lookup ctx name with Some expr' -> expr' | None -> expr) *)
(*   | `List elems -> `List (exp_all elems) *)
(*   | `Let (name, bound, body) -> expand (Ctx.bind ctx name (expand ctx bound)) body *)
(*   | `Lambda (args, body) -> *)
(*      let ctx' = List.fold args ~init:ctx ~f:(fun ctx' arg -> Ctx.unbind ctx' arg) in *)
(*      `Lambda (args, expand ctx' body) *)
(*   | `Apply (func, args) -> *)
(*      let args' = exp_all args in *)
(*      let func' = exp func in *)
(*      (match func' with *)
(*       | `Lambda (lambda_args, body) -> *)
(*          let ctx' = List.fold2_exn lambda_args args' ~init:ctx *)
(*                                    ~f:(fun ctx' arg_name arg_val -> Ctx.bind ctx' arg_name arg_val) in *)
(*          expand ctx' body *)
(*       | _ -> verify_error (sprintf "Tried to apply a non-lambda expression: %s" *)
(*                                    (expr_to_string expr))) *)
(*   | `Op (op, args) -> `Op (op, exp_all args) *)
(*   | `Num _ | `Bool _ -> expr *)

(* let rec typ_to_z3 (zctx: Z3.context) (typ: typ) : Z3.Sort.sort = *)
(*   match typ with *)
(*   | Const_t Num_t -> Z3.Arithmetic.Integer.mk_sort zctx *)
(*   | Const_t Bool_t -> Z3.Boolean.mk_sort zctx *)
(*   | App_t ("list", [elem_typ]) -> Z3.Z3List.mk_list_s zctx (typ_to_string typ) (typ_to_z3 zctx elem_typ) *)
(*   | App_t ("list", _) -> verify_error "Wrong number of arguments to list." *)
(*   | App_t (const, _) -> verify_error (sprintf "Type constructor %s is not supported." const) *)
(*   | Var_t {contents = Link typ'} -> typ_to_z3 zctx typ' *)
(*   | Var_t {contents = Free _} *)
(*   | Var_t {contents = Quant _} *)
(*   | Arrow_t _ -> verify_error (sprintf "Z3 types must be concrete: %s" (typ_to_string typ)) *)

(* let typed_id_to_z3 zctx tid = *)
(*   let id, typ = tid in *)
(*   let sort = typ_to_z3 zctx typ in *)
(*   Z3.Expr.mk_const_s zctx id sort *)

(* let rec expr_to_z3 (zctx: Z3.context) z3ectx expr = *)
(*   match expr with *)
(*   | Num (x, _) -> Z3.Arithmetic.Integer.mk_numeral_i zctx x *)
(*   | Bool (x, _) -> Z3.Boolean.mk_val zctx x *)
(*   | List (x, t) -> *)
(*      let sort = typ_to_z3 zctx t in *)
(*      let nil = Z3.Z3List.nil sort in *)
(*      let cons = Z3.Z3List.get_cons_decl sort in *)
(*      List.fold_right x ~init:nil *)
(*                      ~f:(fun elem acc -> *)
(*                          let z3_elem = expr_to_z3 zctx z3ectx elem in *)
(*                          Z3.FuncDecl.apply cons [z3_elem; acc]) *)
(*   | Id (x, _) -> Ctx.lookup_exn z3ectx x *)
(*   | Op ((op, args), _) -> *)
(*      let open Op in *)
(*      (match op, (List.map ~f:(expr_to_z3 zctx z3ectx) args) with *)
(*       | Plus, z3_args -> Z3.Arithmetic.mk_add zctx z3_args *)
(*       | Minus, z3_args-> Z3.Arithmetic.mk_sub zctx z3_args *)
(*       | Mul, z3_args  -> Z3.Arithmetic.mk_mul zctx z3_args *)
(*       | Div, [a1; a2] -> Z3.Arithmetic.mk_div zctx a1 a2 *)
(*       | Mod, [a1; a2] -> Z3.Arithmetic.Integer.mk_mod zctx a1 a2 *)
(*       | Eq,  [a1; a2] -> Z3.Boolean.mk_eq zctx a1 a2 *)
(*       | Neq, [a1; a2] -> Z3.Boolean.mk_not zctx (Z3.Boolean.mk_eq zctx a1 a2) *)
(*       | Lt,  [a1; a2] -> Z3.Arithmetic.mk_lt zctx a1 a2 *)
(*       | Leq, [a1; a2] -> Z3.Arithmetic.mk_le zctx a1 a2 *)
(*       | Gt,  [a1; a2] -> Z3.Arithmetic.mk_gt zctx a1 a2 *)
(*       | Geq, [a1; a2] -> Z3.Arithmetic.mk_ge zctx a1 a2 *)
(*       | And, z3_args  -> Z3.Boolean.mk_and zctx z3_args *)
(*       | Or, z3_args   -> Z3.Boolean.mk_or zctx z3_args *)
(*       | Not, [a]      -> Z3.Boolean.mk_not zctx a *)
(*       | If, [a; b; c] -> Z3.Boolean.mk_ite zctx a b c *)
(*       | Cons, [a; b]  -> let sort = Z3.Expr.get_sort b in *)
(*                          let cons = Z3.Z3List.get_cons_decl sort in *)
(*                          Z3.FuncDecl.apply cons [a; b] *)
(*       | Car, [a]      -> let sort = Z3.Expr.get_sort a in *)
(*                          let head = Z3.Z3List.get_head_decl sort in *)
(*                          Z3.FuncDecl.apply head [a] *)
(*       | Cdr, [a]      -> let sort = Z3.Expr.get_sort a in *)
(*                          let tail = Z3.Z3List.get_tail_decl sort in *)
(*                          Z3.FuncDecl.apply tail [a] *)
(*       | _ -> verify_error "Attempted to convert unsupported operator to Z3.") *)
(*   | Lambda _ *)
(*   | Let _ *)
(*   | Apply _ -> verify_error "(lambda, let, apply) are not supported by Z3." *)

let verify_example target (example: example) : bool =
  let input, result = example in
  let eval expr = Eval.eval ~recursion_limit:10 (Ctx.empty ()) expr in
  (try (eval (target input)) = (eval (target result))
   with 
   | RuntimeError _ -> false
   | Ast.Ctx.UnboundError name -> (* printf "Unbound %s in %s\n" name (expr_to_string (target input)); *) false)

let verify_examples target examples = List.for_all examples ~f:(verify_example target)

(* let verify_constraint (zctx: Z3.context) (target: expr -> expr) (constr: constr) : bool = *)
(*   let open Z3.Solver in *)
(*   let solver = mk_simple_solver zctx in *)

(*   (\* Wrap the constraint in a let containing the definition of the *)
(*   target function and then expand. *\) *)
(*   let body, ids =  *)
(*     let body', ids' = constr in *)
(*     typed_constr ((expand (Ctx.empty ()) (target body')), ids') in *)
  
(*   (\* Generate a correctly typed Z3 constant for each unbound id in the constraint. *\) *)
(*   let z3_consts = List.map ids ~f:(typed_id_to_z3 zctx) in *)

(*   (\* Convert constraint body to a Z3 expression. *\) *)
(*   let z3_constr_body =  *)
(*     let ctx = List.fold2_exn ids z3_consts  *)
(*                              ~init:(Ctx.empty ()) *)
(*                              ~f:(fun acc (id, _) z3c -> Ctx.bind acc id z3c) in *)
(*     expr_to_z3 zctx ctx body in *)

(*   (\* let _ = Printf.printf "%s\n" (Z3.Expr.to_string z3_constr_body) in *\) *)

(*   (\* Add the constraint to the solver and check. *\) *)
(*   add solver [Z3.Boolean.mk_not zctx z3_constr_body]; *)
(*   match check solver [] with *)
(*   | UNSATISFIABLE -> true *)
(*   | UNKNOWN -> verify_error "Z3 returned unknown." *)
(*   | SATISFIABLE -> false *)

(* let verify (examples: example list) (constraints: constr list) (target: expr -> expr) : status = *)
(*   if verify_examples target examples *)
(*   then *)
(*     let zctx = Z3.mk_context [] in *)
(*     try *)
(*       if List.for_all constraints ~f:(verify_constraint zctx target) *)
(*       then Valid *)
(*       else Invalid *)
(*     with VerifyError msg ->  *)
(*       Printf.printf "%s\n" msg;  *)
(*       Error *)
(*   else Invalid *)
