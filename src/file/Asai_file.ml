include Marked

open Bwd

module type S =
sig
  module Code : Asai.Code.S
  val format : splitting_threshold:int -> Code.t Asai.Diagnostic.t -> t
end

module Make (Code : Asai.Code.S) : S with module Code := Code
=
struct
  let format_sections ~splitting_threshold ~additional_marks span =
    let marked_sections =
      match span with
      | None -> Flatter.empty
      | Some sp -> Flatter.singleton (`Highlighted, sp)
    in
    let marked_sections =
      (* add additional_marks *)
      List.fold_right (fun sp -> Flatter.add (`Marked, sp)) additional_marks marked_sections
    in
    List.map Marker.mark_section @@ Flatter.flatten ~splitting_threshold marked_sections

  let format_message ~splitting_threshold ~additional_marks (msg : _ Asai.Span.located) =
    format_sections ~splitting_threshold ~additional_marks msg.loc, msg.value

  let format ~splitting_threshold (d : Code.t Asai.Diagnostic.t) =
    Reader.run @@ fun () ->
    { code = Code.to_string d.code
    ; severity = d.severity
    ; message = format_message ~splitting_threshold ~additional_marks:d.additional_marks d.message
    ; traces = Bwd.map (format_message ~splitting_threshold ~additional_marks:[]) d.traces
    }
end

module Internal =
struct
  module Reader = Reader
  module Flattened = Flattened
  module Flatter = Flatter
  module Marker = Marker
end
