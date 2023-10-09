open Bwd

(** The type of severity. *)
type severity =
  | Hint
  | Info
  | Warning
  | Error
  | Bug

(** The type of text.

    When we render a diagnostic, the layout engine of the rendering backend should be the one making layout choices. Therefore, we cannot pass already formatted strings. Instead, a text is defined to be a function that takes a formatter and uses it to render the content. The following two conditions must be satisfied:
    + {b All string (and character) literals must be encoded using UTF-8.}
    + {b All string (and character) literals must not contain control characters (such as the newline character [\n]).} It is okay to have break hints (such as [@,] and [@ ]) but not literal control characters. This means you should avoid pre-formatted strings, and if you must use them, use {!val:text} to convert newline characters. Control characters include `U+0000-001F` (C0 controls), `U+007F` (backspace) and `U+0080-009F` (C1 controls). These characters are banned because they would mess up the cursor position.

    {i Pro-tip:} to format a text in another text, use [%t]:
    {[
      let t2 = textf "@[<2>The network doesn't seem to work:@ %t@]" t1
    ]}
*)
type text = Format.formatter -> unit

(** A message is a located {!type:text}. *)
type message = text Span.located

(** A backtrace is a (backward) list of messages. *)
type backtrace = message bwd

(** The type of diagnostics. *)
type 'code t = {
  severity : severity;
  (** Severity of the diagnostic. *)
  code : 'code;
  (** The message code. *)
  message : message;
  (** The main message. *)
  backtrace : backtrace;
  (** The backtrace leading to this diagnostic. *)
  additional_messages : message list;
  (** Additional messages relevant to the main message that are not part of the backtrace. *)
}
