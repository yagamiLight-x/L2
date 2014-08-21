open Core.Std
open OUnit2
open Ast

let identity (x: 'a) : 'a = x

let cmp_partition a b =
  let sort_partition p = List.sort ~cmp:Int.compare p in
  let sort_partition_list l = List.map ~f:sort_partition l
                              |> List.sort ~cmp:(List.compare ~cmp:Int.compare) in
  (sort_partition_list a) = (sort_partition_list b)

let m_expr_to_string = function Some e -> expr_to_string e | None -> "None"

(* let vals_to_string (res:(value list * value) list) = *)
(*   let val_to_string (v: value list * value) = *)
(*     let (inputs, result) = v in *)
(*     let inputs_strs = List.map inputs ~f:value_to_string in *)
(*     (Ast.sexp "(" inputs_strs ")") ^ " = " ^ (value_to_string result) in *)
(*   let vals_strs = List.map res ~f:val_to_string in *)
(*   Ast.sexp "[" vals_strs "]" *)

let make_tests ?cmp:(cmp = (=)) ~in_f ~out_f ~in_str ~out_str ~res_str name cases =
  name >:::
    (List.map ~f:(fun (input, output) ->
                  let case_name = Printf.sprintf "%s => %s" (in_str input) (out_str output) in
                  case_name >:: (fun _ -> assert_equal ~printer:res_str ~cmp:cmp
                                                       (out_f output) (in_f input)))
              cases)

let make_solve_tests ?cmp:(cmp = (=)) ~in_f ~out_f ~in_str ~out_str ~res_str name cases =
  name >:::
    (List.map ~f:(fun (input, output) ->
                  let case_name = Printf.sprintf "%s => %s" (in_str input) (out_str output) in
                  case_name >:: (fun ctx ->
                                 skip_if (not (test_solve ctx)) "Skipping solve tests.";
                                 assert_equal ~printer:res_str ~cmp:cmp (out_f output) (in_f input)))
              cases)

let test_parse_expr =
  let open Op in
  make_tests ~in_f:Util.parse_expr ~out_f:identity
              ~in_str:identity ~out_str:expr_to_string ~res_str:expr_to_string
              "parse_expr"
              [ "1", `Num 1;
                "#t", `Bool true;
                "#f", `Bool false;
                "[]", `List [];
                "[1]", `List [`Num 1];
                "[1 2]", `List [`Num 1; `Num 2];
                "[[]]", `List [`List []];
                "[[1]]", `List [`List [`Num 1]];
                "a", `Id "a";
                "test", `Id "test";
                "(+ (+ 1 2) 3)", `Op (Plus, [`Op (Plus, [`Num 1; `Num 2]); `Num 3;]);
                "(let f (lambda (x) (if (= x 0) 0 (+ (f (- x 1)) 1))) (f 0))",
                `Let ("f", `Lambda (["x"],
                                    `Op (If, [`Op (Eq, [`Id "x"; `Num 0]);
                                              `Num 0;
                                              `Op (Plus, [`Apply (`Id "f",
                                                                  [`Op (Minus, [`Id "x";
                                                                                `Num 1])]);
                                                          `Num 1])])),
                      `Apply (`Id "f", [`Num 0]));
                "(+ 1 2)", `Op (Plus, [`Num 1; `Num 2]);
                "(cons 1 [])", `Op (Cons, [`Num 1; `List []]);
                "(cons 1 [2])", `Op (Cons, [`Num 1; `List [`Num 2]]);
                "(cdr [])", `Op (Cdr, [`List []]);
                "(cdr [1 2])", `Op (Cdr, [`List [`Num 1; `Num 2;]]);
                "(f 1 2)", `Apply (`Id "f", [`Num 1; `Num 2]);
                "(> (f 1 2) 3)", `Op (Gt, [`Apply (`Id "f", [`Num 1; `Num 2]); `Num 3]);
                "(map x7 f6)", `Apply (`Id "map", [`Id "x7"; `Id "f6"]);
              ]

let test_parse_typ =
  make_tests ~in_f:Util.parse_typ ~out_f:identity
              ~in_str:identity ~out_str:typ_to_string ~res_str:typ_to_string
              "parse_typ"
              [ "num", Const_t Num;
              ]

let test_parse_example =
  make_tests ~in_f:Util.parse_example ~out_f:identity
              ~in_str:identity ~out_str:example_to_string ~res_str:example_to_string
              "parse_example"
              [ "(f 1) -> 1", ((`Apply (`Id "f", [`Num 1])), `Num 1);
                "(f (f 1)) -> 1", ((`Apply (`Id "f", [`Apply (`Id "f", [`Num 1])])), `Num 1);
                "(f []) -> []", ((`Apply (`Id "f", [`List []])), (`List []));
              ]

let test_eval =
  make_tests ~in_f:(fun str -> str |> Util.parse_expr |> (Eval.eval (Ctx.empty ())))
             ~out_f:identity
              ~in_str:identity ~out_str:Eval.value_to_string ~res_str:Eval.value_to_string
              "eval"
              [ "1", `Num 1;
                "#t", `Bool true;
                "#f", `Bool false;
                "[1]", `List [`Num 1];
                "(+ 1 2)", `Num 3;
                "(- 1 2)", `Num (-1);
                "(* 1 2)", `Num 2;
                "(/ 4 2)", `Num 2;
                "(% 4 2)", `Num 0;
                "(= 4 2)", `Bool false;
                "(= 4 4)", `Bool true;
                "(> 4 2)", `Bool true;
                "(> 4 4)", `Bool false;
                "(>= 4 2)", `Bool true;
                "(>= 4 4)", `Bool true;
                "(>= 4 5)", `Bool false;
                "(cons 4 [])", `List [`Num 4];
                "(cons 4 [1])", `List [`Num 4; `Num 1];
                "(car [1])", `Num 1;
                "(cdr [1 2])", `List [`Num 2];
                "(if #t 1 2)", `Num 1;
                "(if #f 1 2)", `Num 2;
                "(let a 1 (+ 1 a))", `Num 2;
                "(let a 5 (let b 2 (* a b)))", `Num 10;
                "(let a 5 (let a 2 (+ a 1)))", `Num 3;
                "(let a (* 3 4) (+ a 1))", `Num 13;
                "(let f (lambda (x) (+ 1 x)) (f 1))", `Num 2;
                "(let f (lambda (x y) (+ y x)) (f 1 2))", `Num 3;
                "(let f (lambda (x) (lambda (y) (+ x y))) ((f 1) 2))", `Num 3;
                "(let f (lambda (x) (+ x 1)) (let g (lambda (x) (+ 1 x)) (f (g 1))))", `Num 3;
                "(let f (lambda (x) (if (= x 0) 0 (f (- x 1)))) (f 0))", `Num 0;
                "(let f (lambda (x) (if (= x 0) 0 (f (- x 1)))) (f 5))", `Num 0;
                "(foldr [1 2 3] (lambda (a e) (+ a e)) 0)", `Num 6; (* Sum *)
                "(foldr [[1] [2 1] [3 2 1]] (lambda (a e) (cons (car e) a)) [])",
                `List [`Num 1; `Num 2; `Num 3]; (* Firsts *)
                "(foldl [1 2 3] (lambda (a e) (+ a e)) 0)", `Num 6; (* Sum *)
                "(foldl [[1] [2 1] [3 2 1]] (lambda (a e) (cons (car e) a)) [])",
                `List [`Num 3; `Num 2; `Num 1]; (* Rev-firsts *)
                "(filter [] (lambda (e) (> 3 e)))", `List [];
                "(filter [1 2 3 4] (lambda (e) (> 3 e)))", `List [`Num 1; `Num 2];
                "(filter [1 2 3 4] (lambda (e) (= 0 (% e 2))))", `List [`Num 2; `Num 4];
                "(map [] (lambda (e) (+ e 1)))", `List [];
                "(map [1] (lambda (e) (+ e 1)))", `List [`Num 2];
                "(map [1 2] (lambda (e) (+ e 1)))", `List [`Num 2; `Num 3];
                "(map [0 1 0] (lambda (e) (= e 0)))",
                `List [`Bool true; `Bool false; `Bool true];
              ]

let test_unify =
  let open Infer in
  make_tests ~cmp:(Sub.equal (=))
             ~in_f:(fun (t1, t2) -> unify t1 t2) ~out_f:identity
             ~in_str:(fun (t1, t2) -> (typ_to_string t1) ^ ", " ^ (typ_to_string t2))
             ~out_str:to_string ~res_str:to_string
             "unify"
             [ 
               (Const_t Num, Const_t Num), Sub.empty;
               (Var_t (Free 1), Const_t Num), Sub.singleton 1 (Const_t Num);
               (Var_t (Free 1), Const_t Num), Sub.singleton 1 (Const_t Num);
               (Var_t (Free 1), Var_t (Free 1)), Sub.empty;
               (Var_t (Quant "test"), Var_t (Quant "test")), Sub.empty;
               (Var_t (Free 1), Var_t (Quant "test")), Sub.singleton 1 (Var_t (Quant "test"));
               (Arrow_t ([Const_t Num; Const_t Num], Const_t Num),
                Arrow_t ([Var_t (Free 1); Var_t (Free 2)], Var_t (Free 3))),
               Sub.of_alist_exn [1, Const_t Num; 2, Const_t Num; 3, Const_t Num];
               (Arrow_t ([Var_t (Free 1); App_t ("list", [Var_t (Free 1)])], 
                         App_t ("list", [Var_t (Free 1)])),
                Arrow_t ([Const_t Num; App_t ("list", [Var_t (Free 2)])], 
                         App_t ("list", [Var_t (Free 3)]))),
               Sub.of_alist_exn [1, Const_t Num; 2, Const_t Num; 3, Const_t Num];
               (App_t ("tuple", [Var_t (Free 1); Var_t (Free 1)]),
                App_t ("tuple", [Const_t Num; Var_t (Free 2)])),
               Sub.of_alist_exn [1, Const_t Num; 2, Const_t Num];
             ]

let test_typeof =
  make_tests 
    ~in_f:(fun str -> Util.parse_expr str |> (Infer.infer (Ctx.empty ())) |> Infer.normalize)
    ~out_f:(fun str -> Util.parse_typ str |> Infer.normalize)
    ~in_str:identity ~out_str:identity
    ~res_str:typ_to_string
    "typeof"
    [ "1", "num";
      "#t", "bool";
      "#f", "bool";
      "(+ 1 2)", "num";
      "(< 1 2)", "bool";
      "(cons 1 [])", "list[num]";
      "(cons 1 [1 2 3])", "list[num]";
      "(car [1 2 3])", "num";
      "(cdr [1 2 3])", "list[num]";
      "(car (cdr [1 2 3]))", "num";
      "(let f (lambda (x) (+ 1 x)) f)", "num -> num";
      "(let f (lambda (x y) (+ x y)) f)", "(num, num) -> num";
      "(let g (lambda (x y f) (+ x (f y))) g)", "(num, a, (a -> num)) -> num";
      "(lambda (x y f) (+ x (f y)))", "(num, a, (a -> num)) -> num";
      "(let g (lambda (x y) (lambda (f) (f x y))) g)", "(a, b) -> (((a, b) -> c) -> c)";
      "(let f (lambda (x) (cons x [])) f)", "t1 -> list[t1]";
      "(map [] (lambda (x) (+ x 1)))", "list[num]";
      "(map [1 2 3] (lambda (x) (+ x 1)))", "list[num]";
      "(let f (lambda (x y) (+ x y)) (f 1 2))", "num";
      "(let f (lambda (x) (+ x 1)) (f 1))", "num";
      "(let f (lambda (x) (+ x 1)) (f 1))", "num";
      "(lambda (x) (let y x y))", "t1 -> t1";
      "(lambda (x) (let y (lambda (z) z) y))", "t0 -> (t1 -> t1)";
      "(let f (lambda (x) x) (let id (lambda (y) y) (= f id)))", "bool";
      "(let apply (lambda (f x) (f x)) apply)", "((a -> b), a) -> b";
      "(lambda (f) (let x (lambda (g y) (let z (g y) (= f g))) x))", "(a -> b) -> (((a -> b), a) -> bool)";
      "(lambda (l x) (= [x] l))", "(list[a], a) -> bool";
      "(let a 0 (let b 1 (lambda (x) (cons a [b]))))", "a -> list[num]";
      "(lambda (y) (if (= 0 y) 0 1))", "num -> num";
      "(lambda (y) (= y 1))", "num -> bool";
    ]

let test_fold_constants =
  make_tests ~in_f:(fun str -> str |> Util.parse_expr |> Rewrite.fold_constants)
              ~out_f:(fun str -> Some (Util.parse_expr str))
              ~in_str:identity ~out_str:identity
              ~res_str:m_expr_to_string
              "fold_constants"
              [ "1", "1";
                "#f", "#f";
                "[]", "[]";
                "[1 2]", "[1 2]";
                "(+ 1 2)", "3";
                "(+ (* 0 5) (/ 4 2))", "2";
                "(+ a (- 4 3))", "(+ a 1)";
                "(lambda (x) (+ x (* 1 5)))", "(lambda (x) (+ x 5))";
                "(lambda (x) (+ 1 (* 1 5)))", "6";
              ]

let test_rewrite =
  make_tests ~in_f:(fun str -> str |> Util.parse_expr |> Rewrite.rewrite)
              ~out_f:(fun str -> Some (Util.parse_expr str))
              ~in_str:identity ~out_str:identity
              ~res_str:m_expr_to_string
              "rewrite"
              [ "1", "1";
                "#f", "#f";
                "[]", "[]";
                "[1 2]", "[1 2]";
                "(+ x 0)", "x";
                "(+ 0 x)", "x";
                "(+ 1 x)", "(+ 1 x)";
                "(- x 0)", "x";
                "(* x 0)", "0";
                "(* 0 x)", "0";
                "(* x 1)", "x";
                "(* 1 x)", "x";
                "(/ x 1)", "x";
                "(/ 0 x)", "0";
                "(/ x x)", "1";
                "(% 0 x)", "0";
                "(% x 1)", "0";
                "(% x x)", "0";
                "(!= x y)", "(!= x y)";
                "(!= x x)", "#f";
                "(+ (- y x) x)", "y";
                "(- (+ y x) x)", "y";
                "(- (+ y x) y)", "x";
                "(= (= x y) #f)", "(!= x y)";
              ]

let test_normalize =
  make_tests ~in_f:(fun str -> str |> Util.parse_expr |> Rewrite.normalize) ~out_f:Util.parse_expr
              ~in_str:identity ~out_str:identity ~res_str:expr_to_string
    "normalize"
    [ "(+ 1 (+ 2 3))", "(+ 1 2 3)";
      "(+ (+ 1 2) (+ 3 4))", "(+ 1 2 3 4)";
      "(+ (* (* 0 1) 2) (+ 3 4))", "(+ (* 0 1 2) 3 4)";
      "(+ 1 (- 2 3))", "(+ (- 2 3) 1)";
      "(- 1 (- 2 3))", "(- 1 (- 2 3))";
    ]

let test_denormalize =
  make_tests ~in_f:(fun str -> str |> Util.parse_expr |> Rewrite.denormalize) ~out_f:Util.parse_expr
              ~in_str:identity ~out_str:identity ~res_str:expr_to_string
    "normalize"
    [ "(+ 1 2 3)", "(+ 1 (+ 2 3))";
      "(+ 1 2 3 4)", "(+ 1 (+ 2 (+ 3 4)))";
      "(+ (* 0 1 2) 3 4)", "(+ (* 0 (* 1 2)) (+ 3 4))";
    ]

let test_straight_solve =
  make_solve_tests
    ~in_f:(fun (_, example_strs, init_strs) ->
           let solution = Search.solve ~init:(List.map init_strs ~f:Util.parse_expr)
                                       (List.map example_strs ~f:Util.parse_example) [] in
           (solution :> expr option))
    ~out_f:(fun res_str -> Some (Util.parse_expr res_str))
    ~in_str:(fun (name, _, _) -> name) ~out_str:identity
    ~res_str:(fun res -> match res with
                         | Some expr -> expr_to_string expr
                         | None -> "")
    "straight_solve"
    [
      ("plus", ["(f 1 1) -> 2";
                "(f 2 1) -> 3"], []),
      "(define f (lambda (x0:num x1:num):num (+ x0 x1)))";

      ("max", ["(f 3 5) -> 5";
               "(f 5 3) -> 5"], []),
      "(define f (lambda (x0:num x1:num):num (if (< x0 x1) x1 x0)))";

      ("second", ["(f [1 2]) -> 2";
                  "(f [1 3]) -> 3"], []),
      "(define f (lambda (x0:[num]):num (car (cdr x0))))";

      ("even", ["(f 1) -> #f";
                "(f 2) -> #t";
                "(f 3) -> #f";
                "(f 4) -> #t";
               ], ["0"; "2"]),
      "(define f (lambda (x0:num):bool (= (% x0 2) 0)))";
    ]

let partition_to_string = List.to_string ~f:(List.to_string ~f:Int.to_string)
let test_partition =
  make_tests ~in_f:Util.partition ~out_f:identity
              ~in_str:Int.to_string ~out_str:partition_to_string ~res_str:partition_to_string
              ~cmp:cmp_partition
              "test_partition"
              [ 0, [];
                1, [[1]];
                2, [[2]; [1; 1]];
                3, [[3]; [1; 2]; [1; 1; 1]];
              ]

let test_m_partition =
  "test_m_partition" >:::
    (List.map ~f:(fun (n, m, p) ->
                  let title = Printf.sprintf "%s -> %s"
                                             (Int.to_string n)
                                             (partition_to_string p) in
                  title >:: (fun _ -> assert_equal ~cmp:cmp_partition (Util.m_partition n m) p))
              [ 3, 1, [[3]];
                3, 2, [[1; 2]];
                3, 3, [[1; 1; 1]];
    ])

(* let test_typeof_value = *)
(*   make_tests ~in_f:Eval.typeof_value ~out_f:identity *)
(*               ~in_str:value_to_string ~out_str:typ_to_string ~res_str:typ_to_string *)
(*               "typeof_value" *)
(*               [ `Num 1, Num_t; *)
(*                 `Bool true, Bool_t; *)
(*                 `List ([`Num 1; `Num 2], Num_t), List_t Num_t; *)
(*                 `List ([`List ([`Num 1; `Num 2], Num_t)], List_t Num_t), List_t (List_t Num_t); *)
(*               ] *)

(* let test_typeof_expr = *)
(*   make_tests ~in_f:(fun ex -> ex *)
(*                               |> Util.parse_expr *)
(*                               |> Eval.typeof_expr (Ctx.empty ())) *)
(*              ~out_f:identity *)
(*              ~in_str:identity ~out_str:typ_to_string ~res_str:typ_to_string *)
(*              "typeof_expr" *)
(*              [ "(lambda (x:num y:[num]):[num] (cons x y))", Arrow_t ([Num_t; List_t Num_t], List_t Num_t); *)
(*              ] *)

(* let test_signature = *)
(*   make_tests ~in_f:(fun exs -> exs |> List.map ~f:Util.parse_example |> Search.signature) *)
(*              ~out_f:identity *)
(*              ~in_str:(fun exs -> "[" ^ (String.concat ~sep:"; " exs) ^ "]") *)
(*              ~out_str:typ_to_string ~res_str:typ_to_string *)
(*              "signature" *)
(*              [ ["(f 1) -> 1"; "(f 2) -> 2"], Arrow_t ([Num_t], Num_t); *)
(*                ["(f #f 0) -> 1"; "(f #t 5) -> 2"], Arrow_t ([Bool_t; Num_t], Num_t); *)
(*                ["(f 1) -> 1"; "(f (f 2)) -> 2"], Arrow_t ([Num_t], Num_t); *)
(*                ["(f 1 []:num) -> [1]"; "(f 1 (f 2 []:num)) -> [2 1]"], *)
(*                Arrow_t ([Num_t; List_t Num_t], (List_t Num_t)); *)
(*                ["(f2 [0] 0) -> [0]"; *)
(*                 "(f2 (f2 [1 0] 1) 0) -> [1 0 0]"; *)
(*                 "(f2 (f2 (f2 [1 0 2] 1) 2) 0) -> [1 0 2 3 4]"; *)
(*                 "(f2 [0] 0) -> [0]"; *)
(*                 "(f2 (f2 [1 0] 1) 0) -> [1 0 0]"; *)
(*                 "(f2 (f2 (f2 [1 0 2] 1) 0) 2) -> [1 0 2 3 4]";], *)
(*                Arrow_t ([List_t Num_t; Num_t], List_t Num_t); *)
(*              ] *)

(* let test_expand = *)
(*   make_tests ~in_f:(fun e -> e |> Util.parse_expr |> Verify.expand (Ctx.empty ())) *)
(*              ~out_f:Util.parse_expr *)
(*              ~in_str:identity ~out_str:identity ~res_str:expr_to_string *)
(*              "expand" *)
(*              [ *)
(*                "(let x 2 (+ x 1))", "(+ 2 1)"; *)
(*                "(let x 3 (lambda (a:num):num (+ a x)))", "(lambda (a:num):num (+ a 3))"; *)
(*                "(let x 3 (lambda (x:num):num (+ 5 x)))", "(lambda (x:num):num (+ 5 x))"; *)
(*                "(define y (let a (+ 1 2) (\* a 3)))", "(define y (\* (+ 1 2) 3))"; *)
(*                "(let x 2 (let x 3 (let x 4 x)))", "4"; *)
(*                "(let x 2 (let x 3 (let x 4 x)))", "4"; *)
(*              ] *)

(* let test_expr_to_z3 = *)
(*   let zctx = Z3.mk_context [] in *)

(*   make_tests ~in_f:(fun e -> e *)
(*                              |> Util.parse_expr *)
(*                              |> Verify.expr_to_z3 zctx (Ctx.empty ())) *)
(*              ~out_f:identity *)
(*              ~in_str:identity ~out_str:Z3.Expr.to_string ~res_str:Z3.Expr.to_string *)
(*              ~cmp:Z3.Expr.equal *)
(*              "expr_to_z3" *)
(*              [ *)
(*                "(+ 1 2)", Z3.Arithmetic.mk_add zctx *)
(*                                                [ (Z3.Arithmetic.Integer.mk_numeral_i zctx 1); *)
(*                                                  (Z3.Arithmetic.Integer.mk_numeral_i zctx 2); ]; *)
(*              ] *)

(* let test_verify = *)
(*   let status_to_str = function *)
(*     | Verify.Invalid -> "Invalid" *)
(*     | Verify.Valid -> "Valid" *)
(*     | Verify.Error -> "Error" in *)
(*   make_tests *)
(*     ~in_f:(fun (fdef_str, cs_strs) -> *)
(*            let fdef = match Util.parse_expr fdef_str with *)
(*              | `Define (n, `Lambda l) -> `Define (n, `Lambda l) *)
(*              | _ -> assert_failure "Not a function definition." in *)
(*            let cs = List.map cs_strs ~f:Util.parse_constr in *)
(*            Verify.verify [] cs fdef) *)
(*     ~out_f:identity *)
(*     ~in_str:(fun (fdef_str, cs_strs) -> String.concat ~sep:", " (fdef_str::cs_strs)) *)
(*     ~out_str:status_to_str ~res_str:status_to_str *)
(*     "verify" *)
(*     [ *)
(*       ("(define f (lambda (x:num):num (+ x 1)))", [ "(forall (a:num) (> (f a) a))" ]), Verify.Valid; *)
(*       ("(define f (lambda (x:num):num (+ x 1)))", [ "(forall (a:num) (= (f a) a))" ]), Verify.Invalid; *)
(*       ("(define f (lambda (x0:num x1:num):num (if (< x0 x1) x1 x0)))", *)
(*        [ "(forall (a:num b:num) (>= (f a b) a))"; *)
(*          "(forall (a:num b:num) (>= (f a b) b))" ]), Verify.Valid; *)
(*       ("(define f (lambda (x0:num x1:num):num (if (< x0 x1) x1 x0)))", *)
(*        [ "(forall (a:num b:num) (>= (f a b) a))"; *)
(*          "(forall (a:num b:num) (>= (f a b) b))"; *)
(*          "(forall (a:num b:num) (= (f a b) b))"; *)
(*       ]), Verify.Invalid; *)
(*       ("(define f (lambda (x:num):bool (= (% x 2) 0)))", *)
(*        [ "(forall (a:num) (= (f (\* 2 a)) #t))" ]), Verify.Valid; *)
(*       ("(define f (lambda (x:num y:[num]):[num] (cons x y)))", *)
(*        [ "(forall (a:num b:[num]) (= (car (f a b)) a))" ]), Verify.Valid; *)
(*     ] *)

(* let test_sat_solver = *)
(*   make_tests *)
(*     ~in_f:(fun (f_str, exs) -> SymbSolver.sat_solve (Util.parse_expr f_str) exs) *)
(*     ~out_f:Util.parse_expr *)
(*     ~in_str:(fun (f_str, exs) -> f_str ^ " " ^ (vals_to_string exs)) *)
(*     ~out_str:identity *)
(*     ~res_str:expr_to_string *)
(*     "sat_solver" *)
(*     [ *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [[`Num 1; `Num 2], `Num 3]), "(+ (+ x y) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [[`Num 6; `Num 7], `Num 8]), "(+ (+ x y) -5)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ (+ x y) z1) z2))", [[`Num 1;`Num 2],`Num 3]), "(+ (+ (+ x y) 0) 0)"; *)
(*     ] *)

(* let test_symb_solver = *)
(*   make_tests *)
(*     ~in_f:(fun (f_str, constr_strs, exs) -> *)
(*            let f = Util.parse_expr f_str in *)
(*            let constrs = List.map constr_strs ~f:Util.parse_expr in *)
(*            SymbSolver.symb_solve f constrs exs) *)
(*     ~out_f:Util.parse_expr *)
(*     ~in_str:(fun (f_str, constr_strs, exs) -> *)
(*              Printf.sprintf "%s, %s, %s" f_str (String.concat ~sep:" " constr_strs) (vals_to_string exs)) *)
(*     ~out_str:identity *)
(*     ~res_str:expr_to_string *)
(*     "symb_solver" *)
(*     [ *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ x y) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [ "(< z 1)" ], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ x y) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [ "(< z 1)" ], [[`Num 6; `Num 7], `Num 8]), *)
(*       "(+ (+ x y) -5)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [ "(< z 1)"; "(> z (- 0 1))" ], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ x y) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ (+ x y) z1) z2))", [ "(< z1 2)"; "(<z2 2)" ], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ (+ x y) 0) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ (+ x y) z1) z2))", [ "(< z1 (- 0 2))"; "(> z2 2)" ], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ (+ x y) -3) 3)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ x y) z))", [ "(< (f 1 2) 4)" ], [[`Num 1; `Num 2], `Num 3]), *)
(*       "(+ (+ x y) 0)"; *)
(*       ("(lambda (x:num y:num):num (+ (+ (\* x z1) z2) y))", [ "(< (f 2 3) 4)"; "(< 0 z2)"], [[`Num 1; `Num 2], `Num 0]), *)
(*       "(+ (+ (\* x -3) 1) y)"; *)
(*     ] *)

let () = run_test_tt_main
           ("test-suite" >:::
              [
                test_parse_expr;
                test_parse_typ;
                test_parse_example;

                test_eval;
                (* test_unify; *)
                test_typeof;
                (* test_signature; *)

                (* test_expand; *)
                (* test_expr_to_z3; *)
                (* test_verify; *)

                test_partition;
                test_m_partition;

                test_fold_constants;
                test_rewrite;
                test_normalize;
                test_denormalize;

                (* test_sat_solver; *)
                (* test_symb_solver; *)

                (* test_straight_solve; *)
           ]);
