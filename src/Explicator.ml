open Bwd
open Bwd.Infix

open Explication
include ExplicatorSigs

let to_start_of_line (pos : Span.position) = {pos with offset = pos.start_of_line}

module Make (R : Reader) (Style : Style) = struct
  type position = Span.position

  (** [find_eol_traditional pos] finds the position of the next ['\n']. If the end of file is reached before ['\n'], then the position of the end of the file is returned. *)
  let find_eol_traditional ~file ~eof next =
    let rec go i =
      if i >= eof then
        eof, 0
      else
        match R.unsafe_get file i with
        | '\n' -> i, 1 (* LF *)
        | '\r' ->
          if i+1 < eof && R.unsafe_get file (i+1) = '\n'
          then i, 2 (* CRLF *)
          else i, 1 (* CR *)
        | _ ->
          go (i+1)
    in
    go next

  (** [find_eol_unicode pos] finds the position of the next ['\n']. If the end of file is reached before ['\n'], then the position of the end of the file is returned. *)
  let find_eol_unicode ~file ~eof next =
    let rec go i =
      if i >= eof then
        eof, 0
      else
        match R.unsafe_get file i with
        | '\n' (* LF *) | '\x0b' (* VT *) | '\x0c' (* FF *) -> i, 1
        | '\r' ->
          if i+1 < eof && R.unsafe_get file (i+1) = '\n'
          then i, 2 (* CRLF *)
          else i, 1 (* CR *)
        | '\xc2' ->
          if i+1 < eof && R.unsafe_get file (i+1) = '\x85'
          then i, 2 (* NEL *)
          else go (i+1)
        | '\xe2' ->
          if i+2 < eof && R.unsafe_get file (i+1) = '\x80' &&
             (let c2 = R.unsafe_get file (i+2) in c2 = '\xa8' || c2 = '\xa9')
          then i, 3 (* LS and PS *)
          else go (i+1)
        | _ ->
          go (i+1)
    in
    go next

  (** Skip the ['\n'] character, assuming that [eol] is not the end of file *)
  let eol_to_next_line shift (pos : position) : position =
    { file_path = pos.file_path;
      (* Need to update our offset to skip the newline char *)
      offset = pos.offset + shift;
      start_of_line = pos.offset + shift;
      line_num = pos.line_num + 1 }

  let read_between ~file begin_ end_ : string =
    String.init (end_ - begin_) @@ fun i ->
    R.unsafe_get file (begin_ + i)

  type explicator_state =
    { lines : (string, Style.t) styled list bwd
    ; segments : (string, Style.t) styled bwd
    ; current : (Span.position, Style.t) styled
    ; eol : int
    ; eol_shift : int
    }

  let explicate_block ~line_breaking : (Span.position, Style.t) styled list -> Style.t block =
    let find_eol = match line_breaking with `Unicode -> find_eol_unicode | `Traditional -> find_eol_traditional in
    function
    | [] -> invalid_arg "explicate_block: empty block"
    | (p :: _) as ps ->
      let file = R.load p.value.file_path in
      let eof = R.length file in
      let[@tailcall] rec go state : (Span.position, Style.t) styled list -> _ =
        function
        | p::ps when state.current.value.line_num = p.value.line_num ->
          if p.value.offset > eof then raise @@ Unexpected_end_of_file p.value;
          if p.value.offset > state.eol then raise @@ Unexpected_newline p.value;
          (* Still on the same line *)
          let segments =
            state.segments <:
            style state.current.style (read_between ~file state.current.value.offset p.value.offset)
          in
          go { state with segments; current = p } ps
        | ps ->
          (* Shifting to the next line *)
          let lines =
            let segments =
              state.segments <:
              style state.current.style (read_between ~file state.current.value.offset state.eol)
            in
            state.lines <: Bwd.to_list segments
          in
          (* Continue the process if [ps] is not empty. *)
          match ps with
          | [] ->
            assert (Style.is_default state.current.style); lines
          | p :: _ ->
            if p.value.offset > eof then raise @@ Unexpected_end_of_file p.value;
            if p.value.offset <= state.eol then raise @@ Unexpected_line_num_increment p.value
            else if p.value.offset <= state.eol + state.eol_shift then raise @@ Unexpected_position_in_newline p.value;
            (* Okay, p is really on the next line *)
            let current = style state.current.style @@
              eol_to_next_line state.eol_shift {state.current.value with offset = state.eol}
            in
            let eol, eol_shift = find_eol ~file ~eof (state.eol + state.eol_shift) in
            go {lines; segments=Emp; current; eol; eol_shift} ps
      in
      let start_pos = to_start_of_line p.value in
      { start_line_num = start_pos.line_num
      ; lines = Bwd.to_list @@
          let eol, eol_shift = find_eol ~file ~eof p.value.offset in
          go {lines = Emp; segments = Emp; current = style Style.default start_pos; eol; eol_shift} ps
      }

  let[@inline] explicate_blocks ~line_breaking = List.map (explicate_block ~line_breaking)

  let explicate_part ~line_breaking (file_path, bs) : Style.t part =
    { file_path; blocks = explicate_blocks ~line_breaking bs }

  module F = Flattener.Make(Style)

  let explicate ?(line_breaking=`Traditional) ?(splitting_threshold=0) spans =
    List.map (explicate_part ~line_breaking) @@ F.flatten ~splitting_threshold spans
end
