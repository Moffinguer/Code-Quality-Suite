% qs_check.pl - read every term of each file (no execution) to report syntax errors.
%   swipl qs_check.pl <files...>     exit 1 if any file has a syntax error
% why: op/3 directives are honoured so files that define operators parse correctly.
:- use_module(library(main)).
:- initialization(main, main).

main(Argv) :-
    exclude(==('--'), Argv, Files),
    foldl(check_file, Files, 0, Bad),
    ( Bad > 0 -> halt(1) ; halt(0) ).

check_file(File, B0, B) :-
    setup_call_cleanup(open(File, read, In), read_all(File, In, B0, B), close(In)).

read_all(File, In, B0, B) :-
    catch(read_term(In, T, [syntax_errors(error)]), E, (report(File, E), T = '$error')),
    (   T == end_of_file -> B = B0
    ;   T == '$error' -> B1 is B0 + 1, skip_to_dot(In), read_all(File, In, B1, B)
    ;   honour_ops(T), read_all(File, In, B0, B)
    ).

honour_ops((:- op(P, Ty, N))) :- !, catch(op(P, Ty, N), _, true).
honour_ops((:- module(_, Exports))) :- !, forall(member(op(P, Ty, N), Exports), catch(op(P, Ty, N), _, true)).
honour_ops(_).

report(File, error(syntax_error(What), file(_, Line, Col, _))) :- !,
    format("~w:~w:~w: syntax error: ~w~n", [File, Line, Col, What]).
report(File, error(syntax_error(What), stream(_, Line, Col, _))) :- !,
    format("~w:~w:~w: syntax error: ~w~n", [File, Line, Col, What]).
report(File, E) :- format("~w: ~q~n", [File, E]).

skip_to_dot(In) :- catch(read_term(In, _, [syntax_errors(quiet)]), _, true).
