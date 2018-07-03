open Lwt.Infix

type middleware = Request.t -> Request.t

type handler = Request.t -> Response.t

type uri_handler = Re.t list

type route_handler = {
  meth: Cohttp.Code.meth;
  uri_handler: uri_handler;
  handler: handler;
}

type handler_config = route_handler list

let filter_handler_config_by_meth meth handler_config =
  Base.List.filter handler_config (fun (route_handler : route_handler) ->
      route_handler.meth = meth
    )

let uri_separator = Re.char '/'

let uri_handler_composer uri_catcher accumulator =
  uri_separator :: uri_catcher :: accumulator

let compose_uri_handler uri_handler =
  let regex_wit_separator = Base.List.fold_right uri_handler 
      ~f:uri_handler_composer ~init:[] in
  let beginning_regex = [Re.bol] in
  let ending_regex = [Re.opt (Re.char '/'); Re.eol] in
  let final_regex = Base.List.concat [beginning_regex; regex_wit_separator; ending_regex] in
  Re.seq final_regex

let find_route_handler route handler_config =
  Base.List.find handler_config ~f:(fun route_handler ->
      let uri_handler = route_handler.uri_handler in 
      let composed_uri_handler = compose_uri_handler uri_handler in
      let compiled_uri_handler = Re.compile composed_uri_handler in
      Re.execp compiled_uri_handler route
    )

let apply_route_handler route_handler request =
  match route_handler with
  | Some route_handler -> route_handler.handler request
  | None -> Response.make 200 "Default"

let server handler_config =
  let callback _conn req body =
    Request.make req body >>= fun request ->
    let meth = request.meth in
    let route = request.route in
    let filtered_handler_config = filter_handler_config_by_meth meth handler_config in
    let route_handler = find_route_handler route filtered_handler_config in
    let response = apply_route_handler route_handler request in
    let status, body = Response.convert response in
    Cohttp_lwt_unix.Server.respond_string ~status ~body ()
  in
  Cohttp_lwt_unix.Server.create 
    ~mode:(`TCP (`Port 8000)) (Cohttp_lwt_unix.Server.make ~callback ())

let my_route_handler = {
  meth = `GET;
  uri_handler = [Re.str "hello"; Re.str "world"];
  handler = (fun request -> Response.make 200 "Hello World!");
}

let my_handler_config = [my_route_handler]

let () = ignore (Lwt_main.run (server my_handler_config))