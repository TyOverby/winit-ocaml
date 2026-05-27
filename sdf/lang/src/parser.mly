%{
open Ast
%}

%token <float> FLOAT_LIT
%token <string> STRING_LIT
%token <string> IDENT
%token TRUE FALSE
%token LET FN IF ELSE EXPORT
%token FLOAT_TYPE BOOL_TYPE
%token PLUS MINUS STAR SLASH
%token LT GT LTE GTE
%token AND OR
%token EQUALS
%token LPAREN RPAREN LBRACE RBRACE
%token COMMA SEMI COLON DOT
%token UNDERSCORE
%token EOF

%start <Ast.program> program
%type <Ast.block> block

%%

program:
  | stmts = list(stmt) EXPORT e = expr SEMI EOF
    { { stmts; export = e } }

stmt:
  | LET name = IDENT COLON t = type_annot EQUALS value = expr SEMI
    { Let { loc = $startpos; name; type_annot = Some t; value } }
  | LET name = IDENT EQUALS value = expr SEMI
    { Let { loc = $startpos; name; type_annot = None; value } }
  | FN name = IDENT LPAREN params = separated_list(COMMA, param) RPAREN LBRACE body = block RBRACE
    { Fn_decl { loc = $startpos; name; params; body } }

param:
  | name = IDENT COLON t = type_annot
    { { name; type_annot = Some t } }
  | name = IDENT
    { { name; type_annot = None } }

type_annot:
  | FLOAT_TYPE { Float_type }
  | BOOL_TYPE  { Bool_type }

(* block is right-recursive to avoid shift/reduce conflicts with FN.
   When the parser sees FN, it shifts and then disambiguates:
   FN IDENT -> fn_decl statement; FN LPAREN -> anonymous fn expression. *)
block:
  | e = expr
    { { Ast.stmts = []; expr = e } }
  | LET name = IDENT COLON t = type_annot EQUALS value = expr SEMI rest = block
    { let (rest : Ast.block) = rest in
      { Ast.stmts = Let { loc = $startpos; name; type_annot = Some t; value } :: rest.stmts; expr = rest.expr } }
  | LET name = IDENT EQUALS value = expr SEMI rest = block
    { let (rest : Ast.block) = rest in
      { Ast.stmts = Let { loc = $startpos; name; type_annot = None; value } :: rest.stmts; expr = rest.expr } }
  | FN name = IDENT LPAREN params = separated_list(COMMA, param) RPAREN LBRACE body = block RBRACE rest = block
    { let (rest : Ast.block) = rest in
      { Ast.stmts = Fn_decl { loc = $startpos; name; params; body } :: rest.stmts; expr = rest.expr } }

expr:
  | or_expr { $1 }

or_expr:
  | and_expr { $1 }
  | lhs = or_expr OR rhs = and_expr { { loc = $startpos; kind = Binop (Or, lhs, rhs) } }

and_expr:
  | cmp_expr { $1 }
  | lhs = and_expr AND rhs = cmp_expr { { loc = $startpos; kind = Binop (And, lhs, rhs) } }

cmp_expr:
  | add_expr { $1 }
  | lhs = add_expr LT rhs = add_expr  { { loc = $startpos; kind = Binop (Lt, lhs, rhs) } }
  | lhs = add_expr GT rhs = add_expr  { { loc = $startpos; kind = Binop (Gt, lhs, rhs) } }
  | lhs = add_expr LTE rhs = add_expr { { loc = $startpos; kind = Binop (Lte, lhs, rhs) } }
  | lhs = add_expr GTE rhs = add_expr { { loc = $startpos; kind = Binop (Gte, lhs, rhs) } }

add_expr:
  | mul_expr { $1 }
  | lhs = add_expr PLUS rhs = mul_expr  { { loc = $startpos; kind = Binop (Add, lhs, rhs) } }
  | lhs = add_expr MINUS rhs = mul_expr { { loc = $startpos; kind = Binop (Sub, lhs, rhs) } }

mul_expr:
  | unary_expr { $1 }
  | lhs = mul_expr STAR rhs = unary_expr  { { loc = $startpos; kind = Binop (Mul, lhs, rhs) } }
  | lhs = mul_expr SLASH rhs = unary_expr { { loc = $startpos; kind = Binop (Div, lhs, rhs) } }

unary_expr:
  | postfix_expr { $1 }
  | MINUS e = unary_expr { { loc = $startpos; kind = Unary_neg e } }

postfix_expr:
  | primary_expr { $1 }
  | f = postfix_expr LPAREN args = separated_list(COMMA, expr) RPAREN
    { { loc = $startpos; kind = Call (f, args) } }
  | obj = postfix_expr DOT name = IDENT LPAREN args = separated_list(COMMA, expr) RPAREN
    { { loc = $startpos; kind = Method_call (obj, name, args) } }

primary_expr:
  | f = FLOAT_LIT      { { loc = $startpos; kind = Float_lit f } }
  | TRUE                { { loc = $startpos; kind = Bool_lit true } }
  | FALSE               { { loc = $startpos; kind = Bool_lit false } }
  | s = STRING_LIT     { { loc = $startpos; kind = String_lit s } }
  | name = IDENT       { { loc = $startpos; kind = Ident name } }
  | UNDERSCORE          { { loc = $startpos; kind = Placeholder } }
  | LPAREN e = expr RPAREN { e }
  | IF cond = expr LBRACE then_ = block RBRACE ELSE LBRACE else_ = block RBRACE
    { { loc = $startpos; kind = If (cond, then_, else_) } }
  | FN LPAREN params = separated_list(COMMA, param) RPAREN LBRACE body = block RBRACE
    { { loc = $startpos; kind = Fn (params, body) } }
