% qs_pl_lint.pl - static Prolog lint: swipl -q -f none -g main -t halt qs_pl_lint.pl -- FILE...
% Static lint (no directive/goal is executed): syntax errors, singleton variables,
% undefined predicates (library(prolog_xref)). Exit 1 if anything is reported.
:- use_module(library(prolog_xref)).
:- use_module(library(prolog_source)).
:- dynamic issue/0.
main :-
    current_prolog_flag(argv, Argv),
    forall(member(F, Argv), lint(F)),
    ( issue -> halt(1) ; halt(0) ).
report(File, Line, Fmt, Args) :-
    format(user_error, "~w:~w: ", [File, Line]), format(user_error, Fmt, Args), nl,
    ( issue -> true ; assertz(issue) ).
lint(File) :-
    catch(read_all(File), E, ( message_to_codes_(E, M), report(File, 1, "~s", [M]) )),
    catch(xref_source(File, [silent(true)]), _, true),
    forall(( xref_called(File, G, _), \+ xref_defined(File, G, _),
             \+ predicate_property(system:G, defined),
             \+ predicate_property(user:G, defined) ),
           ( functor(G, N, A), report(File, 1, "undefined predicate ~w/~w", [N, A]) )).
read_all(File) :-
    setup_call_cleanup(
        prolog_open_source(File, In),
        read_loop(File, In),
        prolog_close_source(In)).
read_loop(File, In) :-
    catch(prolog_read_source_term(In, T, _Ex, [singletons(S), syntax_errors(error)]), E,
          ( message_to_codes_(E, M), report(File, 1, "syntax: ~s", [M]), T = '$err' )),
    ( T == end_of_file -> true
    ; T == '$err' -> true      % stop at first syntax error (resync is unreliable)
    ; ( nonvar(S), exclude(underscore, S, S1), S1 \== [] ->
          stream_property(In, position(P)), stream_position_data(line_count, P, L),
          findall(N, member(N=_, S1), Ns),
          report(File, L, "singleton variables ~w", [Ns])
      ; true ),
      read_loop(File, In) ).
underscore(N=_) :- sub_atom(N, 0, 1, _, '_').
message_to_codes_(E, Codes) :-
    message_to_codes(E, Codes0) -> Codes = Codes0 ; term_to_atom(E, A), atom_codes(A, Codes).
message_to_codes(E, Codes) :-
    '$messages':translate_message(E, Lines, []), with_output_to(codes(Codes), print_message_lines(current_output, '', Lines)).
