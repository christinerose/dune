open Import
open Memo.O

type t =
  { bin_dir : Path.t
  ; ocaml : Action.Prog.t
  ; ocamlc : Path.t
  ; ocamlopt : Action.Prog.t
  ; ocamldep : Action.Prog.t
  ; ocamlmklib : Action.Prog.t
  ; ocamlobjinfo : Action.Prog.t
  ; ocaml_config : Ocaml_config.t
  ; ocaml_config_vars : Ocaml_config.Vars.t
  ; version : Ocaml.Version.t
  ; builtins : Meta.Simplified.t Package.Name.Map.t Memo.t
  ; lib_config : Lib_config.t
  }

let make_builtins ~ocaml_config ~version =
  Memo.Lazy.create (fun () ->
    let stdlib_dir = Path.of_string (Ocaml_config.standard_library ocaml_config) in
    Meta.builtins ~stdlib_dir ~version)
;;

let of_env_with_findlib name env findlib_config ~which =
  let not_found ?hint prog =
    Action.Prog.Not_found.create ?hint ~context:name ~program:prog ~loc:None ()
  in
  let get_tool_using_findlib_config prog =
    Memo.Option.bind findlib_config ~f:(Findlib_config.tool ~prog)
  in
  let* ocamlc =
    let ocamlc = "ocamlc" in
    get_tool_using_findlib_config ocamlc
    >>= function
    | Some x -> Memo.return x
    | None ->
      which ocamlc
      >>| (function
      | Some x -> x
      | None -> not_found ocamlc |> Action.Prog.Not_found.raise)
  in
  let ocaml_bin = Path.parent_exn ocamlc in
  let get_ocaml_tool prog =
    get_tool_using_findlib_config prog
    >>= function
    | Some x -> Memo.return (Ok x)
    | None ->
      Which.Best_path.memo ~dir:ocaml_bin prog
      >>| (function
      | Some p -> Ok p
      | None ->
        let hint =
          sprintf
            "ocamlc found in %s, but %s/%s doesn't exist (context: %s)"
            (Path.to_string ocaml_bin)
            (Path.to_string ocaml_bin)
            prog
            (Context_name.to_string name)
        in
        Error (not_found ~hint prog))
  in
  let* ocaml_config_vars, ocaml_config =
    let+ vars =
      Process.run_capture_lines ~display:Quiet ~env Strict ocamlc [ "-config" ]
      |> Memo.of_reproducible_fiber
      >>| Ocaml_config.Vars.of_lines
    in
    match
      match vars with
      | Error msg -> Error (Ocaml_config.Origin.Ocamlc_config, msg)
      | Ok vars ->
        let open Result.O in
        let+ ocfg = Ocaml_config.make vars in
        vars, ocfg
    with
    | Ok x -> x
    | Error (Ocaml_config.Origin.Makefile_config file, msg) ->
      User_error.raise ~loc:(Loc.in_file file) [ Pp.text msg ]
    | Error (Ocamlc_config, msg) ->
      User_error.raise
        [ Pp.textf "Failed to parse the output of '%s -config':" (Path.to_string ocamlc)
        ; Pp.text msg
        ]
  and* ocamlopt = get_ocaml_tool "ocamlopt"
  and* ocaml = get_ocaml_tool "ocaml"
  and* ocamldep = get_ocaml_tool "ocamldep"
  and* ocamlmklib = get_ocaml_tool "ocamlmklib"
  and* ocamlobjinfo = get_ocaml_tool "ocamlobjinfo" in
  let version = Ocaml.Version.of_ocaml_config ocaml_config in
  let builtins = make_builtins ~version ~ocaml_config in
  Memo.return
    { bin_dir = ocaml_bin
    ; ocaml
    ; ocamlc
    ; ocamlopt
    ; ocamldep
    ; ocamlmklib
    ; ocamlobjinfo
    ; ocaml_config
    ; ocaml_config_vars
    ; version
    ; lib_config = Lib_config.create ocaml_config ~ocamlopt
    ; builtins = Memo.Lazy.force builtins
    }
;;

let compiler t (mode : Ocaml.Mode.t) =
  match mode with
  | Byte -> Ok t.ocamlc
  | Native -> t.ocamlopt
;;

let best_mode t : Mode.t =
  match t.ocamlopt with
  | Ok _ -> Native
  | Error _ -> Byte
;;

let of_binaries name env binaries =
  let not_found ?hint prog =
    Action.Prog.Not_found.create ?hint ~context:name ~program:prog ~loc:None ()
  in
  let which =
    let map =
      Path.Set.to_list binaries
      |> Filename.Map.of_list_map_exn ~f:(fun binary -> Path.basename binary, binary)
    in
    fun basename -> Filename.Map.find map basename
  in
  let ocamlc =
    let ocamlc = "ocamlc" in
    match which ocamlc with
    | Some x -> x
    | None -> not_found ocamlc |> Action.Prog.Not_found.raise
  in
  let ocaml_bin = Path.parent_exn ocamlc in
  let module Best_path =
    Which.Best_path.Make
      (Monad.Id)
      (struct
        let file_exists path = Path.Set.mem binaries path
      end)
  in
  let get_ocaml_tool prog =
    match Best_path.best_path ~dir:ocaml_bin prog with
    | Some p -> Ok p
    | None ->
      let hint =
        sprintf
          "ocamlc found in %s, but %s/%s doesn't exist (context: %s)"
          (Path.to_string ocaml_bin)
          (Path.to_string ocaml_bin)
          prog
          (Context_name.to_string name)
      in
      Error (not_found ~hint prog)
  in
  let+ ocaml_config_vars, ocaml_config =
    let+ vars =
      Process.run_capture_lines ~display:Quiet ~env Strict ocamlc [ "-config" ]
      |> Memo.of_reproducible_fiber
      >>| Ocaml_config.Vars.of_lines
    in
    match
      match vars with
      | Error msg -> Error (Ocaml_config.Origin.Ocamlc_config, msg)
      | Ok vars ->
        let open Result.O in
        let+ ocfg = Ocaml_config.make vars in
        vars, ocfg
    with
    | Ok x -> x
    | Error (Ocaml_config.Origin.Makefile_config file, msg) ->
      User_error.raise ~loc:(Loc.in_file file) [ Pp.text msg ]
    | Error (Ocamlc_config, msg) ->
      User_error.raise
        [ Pp.textf "Failed to parse the output of '%s -config':" (Path.to_string ocamlc)
        ; Pp.text msg
        ]
  in
  let ocamlopt = get_ocaml_tool "ocamlopt"
  and ocaml = get_ocaml_tool "ocaml"
  and ocamldep = get_ocaml_tool "ocamldep"
  and ocamlmklib = get_ocaml_tool "ocamlmklib"
  and ocamlobjinfo = get_ocaml_tool "ocamlobjinfo" in
  let version = Ocaml.Version.of_ocaml_config ocaml_config in
  let builtins = make_builtins ~version ~ocaml_config in
  { bin_dir = ocaml_bin
  ; ocaml
  ; ocamlc
  ; ocamlopt
  ; ocamldep
  ; ocamlmklib
  ; ocamlobjinfo
  ; ocaml_config
  ; ocaml_config_vars
  ; version
  ; builtins = Memo.Lazy.force builtins
  ; lib_config = Lib_config.create ocaml_config ~ocamlopt
  }
;;
