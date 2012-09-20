open Cow.Html
open O2w_common

type doc_kind =
  | Html
  | Markdown

let extension_of_kind: doc_kind -> string = function
  | Html -> "html"
  | Markdown -> "md"

let kind_of_extension: string -> doc_kind = function
  | "html" -> Html
  | "md" -> Markdown

(* Returns a pair (basename, extension) of the given filename *)
let split_filename (file: string): (string * string) =
  let dot_index = String.rindex file '.' in
  (String.sub file 0 dot_index,
    String.sub file (dot_index + 1) (String.length file - dot_index - 1))

(* Generate the HTML corresponding to a documentation page in the <content>/doc 
   directory *)
let to_links (content_dir: string) (pages: string list)
    : (Cow.Html.link * menu_item) list =

  (* Convert a content page to html *)
  let of_kind kind filename: Cow.Html.t =
    let content = Types.Raw.to_string (Types.Filename.read filename) in
    match kind with
    | "html" -> Cow.Html.of_string content
    | "md" -> Markdown_github.to_html (Markdown_github.of_string content)
  in

  (* Link creation *)
  let aux page =
    let title, extension = split_filename page in
    let source_file = Printf.sprintf "%s/doc/%s.%s" content_dir title extension in
    let source_filename = Types.Filename.of_string source_file in
    let page = of_kind extension source_filename in
    let dest_file = Printf.sprintf "doc/%s.html" title in

    ({ text=title; href=dest_file }, Internal (1, page))
  in

  List.map aux pages

