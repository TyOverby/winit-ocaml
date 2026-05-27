{
open Parser

exception Syntax_error of string
}

let whitespace = [' ' '\t']+
let newline = '\r' | '\n' | "\r\n"
let digit = ['0'-'9']
let ident_start = ['a'-'z' 'A'-'Z' '_']
let ident_char = ['a'-'z' 'A'-'Z' '0'-'9' '_']

rule token = parse
  | whitespace { token lexbuf }
  | newline    { Lexing.new_line lexbuf; token lexbuf }
  | "//"       { line_comment lexbuf }
  | digit+ '.' digit+ as s { FLOAT_LIT (Float.of_string s) }
  | digit+ as s            { FLOAT_LIT (Float.of_string s) }
  | '"'        { string_lit (Buffer.create 16) lexbuf }
  | "let"      { LET }
  | "fn"       { FN }
  | "if"       { IF }
  | "else"     { ELSE }
  | "true"     { TRUE }
  | "false"    { FALSE }
  | "export"   { EXPORT }
  | "float"    { FLOAT_TYPE }
  | "bool"     { BOOL_TYPE }
  | '+'        { PLUS }
  | '-'        { MINUS }
  | '*'        { STAR }
  | '/'        { SLASH }
  | '<'        { LT }
  | '>'        { GT }
  | "<="       { LTE }
  | ">="       { GTE }
  | "&&"       { AND }
  | "||"       { OR }
  | '='        { EQUALS }
  | '('        { LPAREN }
  | ')'        { RPAREN }
  | '{'        { LBRACE }
  | '}'        { RBRACE }
  | ','        { COMMA }
  | ';'        { SEMI }
  | ':'        { COLON }
  | '.'        { DOT }
  | '_'        { UNDERSCORE }
  | ident_start ident_char* as s { IDENT s }
  | eof        { EOF }
  | _ as c     { raise (Syntax_error (Printf.sprintf "unexpected character: %c" c)) }

and line_comment = parse
  | newline { Lexing.new_line lexbuf; token lexbuf }
  | eof     { EOF }
  | _       { line_comment lexbuf }

and string_lit buf = parse
  | '"'       { STRING_LIT (Buffer.contents buf) }
  | '\\' 'n'  { Buffer.add_char buf '\n'; string_lit buf lexbuf }
  | '\\' '\\' { Buffer.add_char buf '\\'; string_lit buf lexbuf }
  | '\\' '"'  { Buffer.add_char buf '"'; string_lit buf lexbuf }
  | [^ '"' '\\']+ as s { Buffer.add_string buf s; string_lit buf lexbuf }
  | eof       { raise (Syntax_error "unterminated string literal") }
  | _         { raise (Syntax_error "invalid escape in string") }
