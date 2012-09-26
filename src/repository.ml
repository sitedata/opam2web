open Cow.Html

(* Graph representation of package dependencies *)
(* type package_node = Types.NV.t * package_edge list *)

(* type package_edge = *)
(*   | Depends_on of (Types.N.t * ((Types.relop * Types.V.t) option)) *)
(*   | Required_by of Types.NV.t *)

(* Load a repository from the local OPAM installation *)
let of_opam repo_name: Path.R.t =
  let global = Path.G.create () in
  let config = File.Config.read (Path.G.config global) in
  let all_repositories = File.Config.repositories config in
  let repo = List.find
    (fun r -> (Types.Repository.name r) = repo_name) all_repositories
  in
  Path.R.create repo

(* Load a repository from a directory *)
let of_path (name: string): Path.R.t =
  Path.R.of_dirname (Types.Dirname.of_string name)

(* Unify multiple versions of the same packages in a list of lists *)
let unify_versions (packages: Types.NV.t list): Types.NV.t list list =
  let (unique_packages, rest) = List.fold_left (fun (acc, pkgs) pkg ->
      match pkgs with
      | [] -> (acc, [pkg])
      | h :: r when (Types.NV.name h = Types.NV.name pkg) -> (acc, pkg :: pkgs)
      | l -> (l :: acc, [pkg]))
    ([], []) packages
  in
  List.rev (rest :: unique_packages)

(* Create an association list (package_name -> reverse_dependencies) *)
let reverse_dependencies (repository: Path.R.t)
    (packages: Types.NV.t list) : (Types.N.t * Types.NV.t list list) list =
  let package_set = Path.R.available_packages repository in
  let packages = Types.NV.Set.elements package_set in
  let revdeps_tbl: (Types.N.t, Types.NV.t) Hashtbl.t =
    Hashtbl.create 300
  in
  (* Fill a hash table with reverse dependecies (required by...) *)
  List.iter (fun pkg ->
      let opam_file = File.OPAM.read (Path.R.opam repository pkg) in
      let dependencies: Debian.Format822.vpkg list =
        List.flatten (File.OPAM.depends opam_file)
      in
      let deps =
        List.map (fun ((name, _), _) -> Types.N.of_string name) dependencies
      in
      List.iter (fun dep -> Hashtbl.add revdeps_tbl dep pkg) deps)
    packages;
  (* Build the association list *)
  let acc, pkg_acc, prev_pkg =
    Hashtbl.fold (fun pkg reqby (acc, pkg_acc, prev_pkg) ->
        match prev_pkg with
        | Some p when p = pkg -> acc, reqby :: pkg_acc, Some pkg
        | Some p -> (p, pkg_acc) :: acc, [reqby], Some pkg
        | None -> acc, [reqby], Some pkg)
      revdeps_tbl ([], [], None)
  in
  (* FIXME: List.rev where necessary *)
  let revdeps = match prev_pkg with
    | Some p -> (p, pkg_acc) :: acc
    | None -> acc
  in
  List.map (fun (p, reqby) -> (p, unify_versions reqby)) revdeps


(* Create a list of package pages to generate for a repository *)
let to_links (repository: Path.R.t): (Cow.Html.link * int * Cow.Html.t) list =
  let package_set = Path.R.available_packages repository in
  let packages = Types.NV.Set.elements package_set in
  let unique_packages = unify_versions packages in
  let reverse_dependencies = reverse_dependencies repository packages in
  let aux package_versions = List.map (fun (pkg: Types.NV.t) ->
      let pkg_name = Types.N.to_string (Types.NV.name pkg) in
      let pkg_version = Types.V.to_string (Types.NV.version pkg) in
      let pkg_href = Printf.sprintf "pkg/%s.%s.html" pkg_name pkg_version in
      let pkg_title = Printf.sprintf "%s %s" pkg_name pkg_version in
      { text=pkg_title; href=pkg_href }, 1,
        (Package.to_html repository unique_packages
            reverse_dependencies package_versions pkg))
    package_versions
  in
  List.flatten (List.map aux unique_packages)

(* Returns a HTML list of the packages in the given repository *)
let to_html (repository: Path.R.t): Cow.Html.t =
  let package_set = Path.R.available_packages repository in
  let packages = Types.NV.Set.elements package_set in
  let unique_packages = unify_versions packages in
  let packages_html =
    List.map (fun (pkg_vers: Types.NV.t list) ->
        let latest_pkg = Package.latest pkg_vers in
        let pkg_name = Types.N.to_string (Types.NV.name latest_pkg) in
        let pkg_version = Types.V.to_string (Types.NV.version latest_pkg) in
        let pkg_href = Printf.sprintf "%s.%s.html" pkg_name pkg_version in
        let pkg_synopsis =
          File.Descr.synopsis
            (File.Descr.read (Path.R.descr repository latest_pkg))
        in
        <:xml<
          <tr>
            <td><a href="$str: pkg_href$">$str: pkg_name$</a></td>
            <td>$str: pkg_version$</td>
            <td>$str: pkg_synopsis$</td>
          </tr>
        >>)
      unique_packages
  in
  <:xml<
    <form class="form-search">
      <div class="input-append">
        <input id="search" class="search-query" type="text" placeholder="Search packages" />
        <button id="search-button" class="btn add-on">
          <i class="icon-search"> </i>
        </button>
      </div>
    </form>
    <table class="table"  id="packages">
      <thead>
        <tr>
          <th>Name</th>
          <th>Version</th>
          <th>Description</th>
        </tr>
      </thead>
      <tbody>
        $list: packages_html$
      </tbody>
    </table>
  >>
