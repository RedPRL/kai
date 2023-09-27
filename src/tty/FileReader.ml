type bigstring = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

module M = Map.Make (String)
module E = Algaeff.State.Make (struct type state = (Unix.file_descr * bigstring) M.t end)

module Internal =
struct
  let load file_path =
    match M.find_opt file_path (E.get ()) with
    | Some (fd, str) -> fd, str
    | None ->
      let fd =
        try Unix.openfile file_path [Unix.O_RDONLY] 0o777
        with _ -> raise @@ Sys_error ("could not open file " ^ file_path)
      in
      let str =
        try Bigarray.array1_of_genarray @@ Unix.map_file fd Bigarray.char Bigarray.c_layout false [|-1|]
        with _ ->
          (* the fd is already open! *)
          (try Unix.close fd with _ -> ());
          raise @@ Sys_error ("could not read file " ^ file_path)
      in
      E.modify (M.add file_path (fd, str));
      fd, str

  let close_all () =
    M.iter (fun _ (fd, _) -> try Unix.close fd with _ -> ()) (E.get ());
    E.set M.empty
end

type file = bigstring

let load file_path =
  snd @@ Internal.load file_path

let length (str : file) =
  Bigarray.Array1.size_in_bytes str

let[@inline] unsafe_get str i =
  Bigarray.Array1.unsafe_get str i

let run f =
  E.run ~init:M.empty @@ fun () ->
  Fun.protect ~finally:Internal.close_all f
