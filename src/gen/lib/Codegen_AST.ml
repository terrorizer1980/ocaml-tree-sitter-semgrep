(*
   Code generator for the AST.ml file.
*)

open Printf
open AST_grammar
open Codegen_util
open Indent.Types

let preamble grammar =
  [
    Line (
      sprintf "\
(* Generated by ocaml-tree-sitter. *)
(*
   %s grammar

   entrypoint: %s
*)

open Ocaml_tree_sitter_run
"
        grammar.name
        grammar.entrypoint
    )
  ]

let rec format_body body : Indent.t =
  match body with
  | Symbol ident -> [Line (translate_ident ident)]
  | String s -> [Line (sprintf "(Loc.t * string (* %S *))" s)]
  | Pattern s -> [Line (sprintf "(Loc.t * string (* %S pattern *))" s)]
  | Blank -> [Line "unit (* blank *)"]
  | Repeat body ->
      [
        Inline (format_body body);
        Block [Line "list (* zero or more *)"]
      ]
  | Repeat1 body ->
      [
        Inline (format_body body);
        Block [Line "list (* one or more *)"]
      ]
  | Choice body_list ->
      [
        Line "[";
        Inline (format_choice body_list);
        Line "]"
      ]
  | Optional body ->
      [
        Inline (format_body body);
        Block [Line "option"]
      ]
  | Seq body_list ->
      format_seq body_list

and format_choice l =
  List.mapi (fun i body ->
    let name = sprintf "Case%i" i in
    Block [
      Line (sprintf "| `%s of" name);
      Block [Block (format_body body)];
    ]
  ) l

and format_seq l =
  let prod =
    List.map (fun body -> Block (format_body body)) l
    |> interleave (Line "*")
  in
  match l with
  | [_] -> prod
  | _ -> [Paren ("(", prod, ")")]

let format_rule pos len (rule : rule) : Indent.t =
  let is_first = (pos = 0) in
  let is_last = (pos = len - 1) in
  let type_ =
    if not is_first then
      "and"
    else
      "type"
  in
  let ppx =
    if is_last then
      [
        Line "[@@deriving show {with_path = false}]";
      ]
    else
      []
  in
  [
    Line (sprintf "%s %s =" type_ (translate_ident rule.name));
    Block (format_body rule.body);
    Inline ppx;
  ]

let format_types grammar =
  List.map (fun rule_group ->
    let len = List.length rule_group in
    List.mapi
      (fun pos x -> Inline (format_rule pos len x))
      rule_group
  ) grammar.rules
  |> List.flatten
  |> interleave (Line "")

let generate_dumper grammar =
  [
    Line "";
    Line (sprintf "let dump root =");
    Block [
      Line (sprintf "print_endline (show_%s root)"
              grammar.entrypoint);
    ]
  ]

let format grammar =
  [
    Inline (preamble grammar);
    Inline (format_types grammar);
    Inline (generate_dumper grammar);
  ]

let generate grammar =
  let tree = format grammar in
  Indent.to_string tree
