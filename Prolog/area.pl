% Practice I — From pixels to the integral (Prolog)
%
% The same mathematics as the Haskell program, expressed as relations:
%
%   pixel(X, Y, ...)          holds iff (X,Y) is black
%   f(X, ..., Altura)         holds iff Altura is consecutive black pixels
%                             from the bottom of column X
%   M                         is the list of every Altura that satisfies f
%   Area                      is the Riemann sum Σ f(x_i) with Δx = 1
%
% Conceptually:  relations → values that satisfy f(x) → M → area

:- encoding(utf8).

main :-
    catch(run, Error, (print_message(error, Error), halt(1))),
    halt(0).

run :-
    current_prolog_flag(argv, Argv),
    (   Argv = [File|_]
    ->  true
    ;   File = 'curva_binaria_P4.pbm'
    ),
    setup_call_cleanup(
        open(File, read, Stream, [type(binary)]),
        read_stream_to_codes(Stream, Codes),
        close(Stream)
    ),
    parse_p4(Codes, W, H, BPR, RasterList),
    string_codes(Raster, RasterList),
    MaxX is W - 1,
    findall(Altura,
            (between(0, MaxX, X), f(X, Raster, W, H, BPR, Altura)),
            M),
    sum_list(M, Area),
    sample_positions(W, 10, Samples),
    format('============================================================~n', []),
    format('  Practice I — Prolog (logic / declarative)~n', []),
    format('============================================================~n', []),
    format('File          : ~w~n', [File]),
    format('Dimensions    : ~d x ~d~n', [W, H]),
    format('Domain        : x = 0 .. ~d~n', [MaxX]),
    format('Area (pixels²): ~d~n~n', [Area]),
    BW is max(1, W // 72),
    BH is max(1, H // 22),
    format('-- Console view of the source curve (downsampled) --~n', []),
    format('Strategy: each glyph is a block of ~dx~d pixels; a cell is black~n', [BW, BH]),
    format('if a majority of sampled pixels in that block are black.~n~n', []),
    render_image(Raster, W, H, BPR),
    nl,
    format('-- Height function M[x] = f(x) (downsampled bars) --~n~n', []),
    render_heights(M),
    nl,
    format('-- Sample values x_i → f(x_i) --~n', []),
    print_samples(M, Samples, 0),
    nl,
    length(M, LenM),
    format('Check: length M = ~d  |  sum M = ~d~n', [LenM, Area]).

% ------------------------------------------------------------------
% Relations: pixel access and f(X, Altura)
% ------------------------------------------------------------------

% pixel(X, Y, Raster, W, H, BPR) holds when the P4 bit at (X,Y) is 1 (black).
% Y = 0 is the top row.  P4 packs 8 pixels per byte, most-significant bit first.
pixel(X, Y, Raster, W, H, BPR) :-
    X >= 0, X < W, Y >= 0, Y < H,
    ByteIx is Y * BPR + X // 8,
    Bit is 7 - (X mod 8),
    I is ByteIx + 1,
    get_string_code(I, Raster, Byte),
    BitVal is (Byte >> Bit) /\ 1,
    BitVal =:= 1.

% f(X, ..., Altura): Altura = consecutive black pixels from the bottom
% of column X until the first white pixel.
f(X, Raster, W, H, BPR, Altura) :-
    Y0 is H - 1,
    count_black(Y0, X, Raster, W, H, BPR, 0, Altura).

count_black(Y, _, _, _, _, _, Acc, Acc) :-
    Y < 0, !.
count_black(Y, X, Raster, W, H, BPR, Acc, Altura) :-
    pixel(X, Y, Raster, W, H, BPR), !,
    Y2 is Y - 1,
    Acc2 is Acc + 1,
    count_black(Y2, X, Raster, W, H, BPR, Acc2, Altura).
count_black(_, _, _, _, _, _, Acc, Acc).

% ------------------------------------------------------------------
% PBM P4 parser
% ------------------------------------------------------------------

parse_p4([0'P, 0'4 | Rest0], W, H, BPR, Raster) :-
    skip_ws_comments(Rest0, Rest1),
    read_int(Rest1, W, Rest2),
    skip_ws_comments(Rest2, Rest3),
    read_int(Rest3, H, Rest4),
    skip_one_ws(Rest4, Raster0),
    BPR is (W + 7) // 8,
    Expected is BPR * H,
    length(Raster, Expected),
    append(Raster, _, Raster0), !.
parse_p4(_, _, _, _, _) :-
    throw(error(syntax_error('Not a valid PBM P4 file'), _)).

skip_ws_comments([35|T], Rest) :-
    !, drop_line(T, T2),
    skip_ws_comments(T2, Rest).
skip_ws_comments([C|T], Rest) :-
    whitespace(C), !,
    skip_ws_comments(T, Rest).
skip_ws_comments(Codes, Codes).

drop_line([10|T], T) :- !.
drop_line([13,10|T], T) :- !.
drop_line([_|T], Rest) :- drop_line(T, Rest).
drop_line([], []).

whitespace(9).
whitespace(10).
whitespace(13).
whitespace(32).

read_int(Codes, N, Rest) :-
    digits(Codes, Digs, Rest),
    Digs \= [],
    number_codes(N, Digs).

digits([C|T], [C|Ds], Rest) :-
    C >= 0'0, C =< 0'9, !,
    digits(T, Ds, Rest).
digits(Codes, [], Codes).

skip_one_ws([C|T], T) :- whitespace(C), !.
skip_one_ws(Codes, Codes).

% ------------------------------------------------------------------
% Console visualisation (spatial sampling / block aggregation)
% ------------------------------------------------------------------

render_image(Raster, W, H, BPR) :-
    BW is max(1, W // 72),
    BH is max(1, H // 22),
    render_rows(0, Raster, W, H, BPR, BW, BH).

render_rows(Y0, Raster, W, H, BPR, BW, BH) :-
    Y0 < H, !,
    render_cols(0, Y0, Raster, W, H, BPR, BW, BH),
    nl,
    Y1 is Y0 + BH,
    render_rows(Y1, Raster, W, H, BPR, BW, BH).
render_rows(_, _, _, _, _, _, _).

render_cols(X0, Y0, Raster, W, H, BPR, BW, BH) :-
    X0 < W, !,
    (   majority_black(X0, Y0, Raster, W, H, BPR, BW, BH)
    ->  put_char('█')
    ;   put_char(' ')
    ),
    X1 is X0 + BW,
    render_cols(X1, Y0, Raster, W, H, BPR, BW, BH).
render_cols(_, _, _, _, _, _, _, _).

majority_black(X0, Y0, Raster, W, H, BPR, BW, BH) :-
    DXM is min(3, BW - 1),
    DYM is min(3, BH - 1),
    findall(1,
            (between(0, DYM, DY),
             between(0, DXM, DX),
             X is X0 + DX, Y is Y0 + DY,
             pixel(X, Y, Raster, W, H, BPR)),
            Blacks),
    length(Blacks, Nb),
    Total is (DXM + 1) * (DYM + 1),
    Nb * 2 >= Total.

render_heights(M) :-
    (   M = []
    ->  format('(empty M)~n', [])
    ;   length(M, N),
        Step is max(1, N // 72),
        sample_every(M, 0, Step, Sampled),
        max_list(Sampled, Peak0),
        Peak is max(1, Peak0),
        format('f(x) ↑  (scaled to max height ~d)~n', [Peak]),
        render_bar_rows(16, Sampled, Peak),
        length(Sampled, Ns),
        n_chars(Ns, '─', Line),
        format('~s~n', [Line]),
        Last is N - 1,
        Pad is max(0, Ns - 12),
        n_chars(Pad, ' ', Spaces),
        format('x →  0~s~d~n', [Spaces, Last])
    ).

sample_every([], _, _, []).
sample_every([H|T], I, Step, [H|R]) :-
    0 =:= I mod Step, !,
    I2 is I + 1,
    sample_every(T, I2, Step, R).
sample_every([_|T], I, Step, R) :-
    I2 is I + 1,
    sample_every(T, I2, Step, R).

render_bar_rows(Row, _, _) :-
    Row < 1, !.
render_bar_rows(Row, Sampled, Peak) :-
    maplist(bar_cell(Row, Peak), Sampled, Cells),
    format('~s~n', [Cells]),
    Row2 is Row - 1,
    render_bar_rows(Row2, Sampled, Peak).

bar_cell(Row, Peak, H, C) :-
    (   H * 16 >= Row * Peak
    ->  C = '█'
    ;   C = ' '
    ).

n_chars(0, _, []) :- !.
n_chars(N, Ch, [Ch|T]) :-
    N > 0,
    N2 is N - 1,
    n_chars(N2, Ch, T).

sample_positions(N, K, Samples) :-
    K > 1, N > 0, !,
    Max is K - 1,
    findall(X,
            (between(0, Max, I),
             X is min(N - 1, (I * (N - 1)) // Max)),
            Samples).
sample_positions(_, _, []).

print_samples(_, [], _).
print_samples(M, [X|Xs], I) :-
    nth0(X, M, Fx),
    format('x_~d = ~d -> f(x_~d) = ~d pixels~n', [I, X, I, Fx]),
    I2 is I + 1,
    print_samples(M, Xs, I2).
