open! Core
module F = Float32_u

type t = #{ lo : F.t
          ; hi : F.t
          }

let zero = #0.s
let one = #1.s
let neg_one = F.neg #1.s
let top = #{ lo = F.nan; hi = F.nan }
let is_top (#{ lo; hi } : t) = F.is_nan lo || F.is_nan hi

(* Normalizing constructor: any NaN endpoint collapses to [top], so [is_top] only ever
   needs to look for NaN. Callers are responsible for [lo <= hi]. *)
let[@inline] make lo hi : t = if F.is_nan lo || F.is_nan hi then top else #{ lo; hi }
let of_point v = make v v

let create ~lo ~hi =
  if F.is_nan lo || F.is_nan hi
  then top
  else if F.O.(lo <= hi)
  then #{ lo; hi }
  else #{ lo = hi; hi = lo }
;;

let contains t v =
  is_top t
  ||
  let #{ lo; hi } = t in
  F.O.(lo <= v) && F.O.(v <= hi)
;;

(* [F.min]/[F.max] return NaN if either argument is NaN, so joining anything with [top]
   stays [top]. *)
let hull (#{ lo = a; hi = b } : t) (#{ lo = c; hi = d } : t) =
  make (F.min a c) (F.max b d)
;;

let sexp_of_t t =
  if is_top t
  then Sexp.Atom "top"
  else (
    let #{ lo; hi } = t in
    Sexp.List [ F.sexp_of_t lo; F.sexp_of_t hi ])
;;

let to_string t =
  if is_top t
  then "[top]"
  else (
    let #{ lo; hi } = t in
    Printf.sprintf "[%s, %s]" (F.to_string lo) (F.to_string hi))
;;

module Bool = struct
  type t = #{ can_be_false : bool
            ; can_be_true : bool
            }

  let of_point b = #{ can_be_false = not b; can_be_true = b }
  let maybe = #{ can_be_false = true; can_be_true = true }
  let definitely_true (#{ can_be_false; can_be_true } : t) = can_be_true && not can_be_false
  let definitely_false (#{ can_be_false; can_be_true } : t) = can_be_false && not can_be_true
  let contains (#{ can_be_false; can_be_true } : t) b = if b then can_be_true else can_be_false

  let hull (#{ can_be_false = f1; can_be_true = t1 } : t) (#{ can_be_false = f2; can_be_true = t2 } : t) =
    #{ can_be_false = f1 || f2; can_be_true = t1 || t2 }
  ;;

  let and_ (#{ can_be_false = f1; can_be_true = t1 } : t) (#{ can_be_false = f2; can_be_true = t2 } : t) =
    #{ can_be_false = f1 || f2; can_be_true = t1 && t2 }
  ;;

  let or_ (#{ can_be_false = f1; can_be_true = t1 } : t) (#{ can_be_false = f2; can_be_true = t2 } : t) =
    #{ can_be_false = f1 && f2; can_be_true = t1 || t2 }
  ;;

  let xor (#{ can_be_false = f1; can_be_true = t1 } : t) (#{ can_be_false = f2; can_be_true = t2 } : t) =
    #{ can_be_false = (t1 && t2) || (f1 && f2); can_be_true = (t1 && f2) || (f1 && t2) }
  ;;

  let to_string t =
    if definitely_true t then "true" else if definitely_false t then "false" else "maybe"
  ;;

  let sexp_of_t t = Sexp.Atom (to_string t)
end

let[@inline] min4 a b c d = F.min (F.min a b) (F.min c d)
let[@inline] max4 a b c d = F.max (F.max a b) (F.max c d)

(* For the arithmetic ops below, the image of a monotone real function evaluated in
   float32 stays inside the float32 evaluation at the interval corners, because IEEE
   rounding is monotone. Evaluating all four corners (rather than just the two that bound
   the result for finite inputs) makes NaN produced by an achievable corner (e.g.
   [inf + -inf]) propagate into the endpoints, collapsing the result to [top] via
   [make]. *)

let add (#{ lo = a; hi = b } : t) (#{ lo = c; hi = d } : t) =
  let open F.O in
  make (min4 (a + c) (a + d) (b + c) (b + d)) (max4 (a + c) (a + d) (b + c) (b + d))
;;

let sub (#{ lo = a; hi = b } : t) (#{ lo = c; hi = d } : t) =
  let open F.O in
  make (min4 (a - c) (a - d) (b - c) (b - d)) (max4 (a - c) (a - d) (b - c) (b - d))
;;

let neg (#{ lo; hi } : t) = #{ lo = F.neg hi; hi = F.neg lo }

(* Both [-0.0] and [+0.0] count as zero: either makes division blow up and multiplication
   against infinity produce NaN. *)
let contains_zero (#{ lo; hi } : t) = F.O.(lo <= zero) && F.O.(zero <= hi)
let contains_inf (#{ lo; hi } : t) = F.is_inf lo || F.is_inf hi

let mul (#{ lo = a; hi = b } as i1 : t) (#{ lo = c; hi = d } as i2 : t) =
  if is_top i1 || is_top i2
  then top
  else if (contains_zero i1 && contains_inf i2) || (contains_zero i2 && contains_inf i1)
  then
    (* An interior point can produce [0 * inf = NaN] even when no corner product does. *)
    top
  else (
    let open F.O in
    make (min4 (a * c) (a * d) (b * c) (b * d)) (max4 (a * c) (a * d) (b * c) (b * d)))
;;

let div (#{ lo = a; hi = b } as i1 : t) (#{ lo = c; hi = d } as i2 : t) =
  if is_top i1 || is_top i2
  then top
  else if contains_zero i2
  then
    (* The quotient is unbounded on either side of the zero, and [0 / 0] is NaN. *)
    top
  else (
    let open F.O in
    make (min4 (a / c) (a / d) (b / c) (b / d)) (max4 (a / c) (a / d) (b / c) (b / d)))
;;

let sqrt (#{ lo; hi } as t : t) =
  if is_top t
  then top
  else if F.O.(lo < zero)
  then
    (* Some inputs are negative, so NaN is an achievable result. *)
    top
  else make (F.sqrt lo) (F.sqrt hi)
;;

let abs (#{ lo; hi } as t : t) =
  if is_top t
  then top
  else if F.O.(lo >= zero)
  then t
  else if F.O.(hi <= zero)
  then neg t
  else make zero (F.max (F.neg lo) hi)
;;

(* Matches the scalar evaluator's [Sign]: 1 for positive, -1 for negative, 0 otherwise
   (zeros of either sign and NaN). It is monotone, so the endpoint signs bound it; [top]
   maps into [-1, 1] rather than [top] because [sign] never returns NaN. *)
let sign_scalar a = if F.O.(a > zero) then one else if F.O.(a < zero) then neg_one else zero

let sign (#{ lo; hi } as t : t) =
  if is_top t then make neg_one one else make (sign_scalar lo) (sign_scalar hi)
;;

let round (#{ lo; hi } as t : t) =
  if is_top t then top else make (F.round_nearest lo) (F.round_nearest hi)
;;

(* Scalar [Min]/[Max] use [F.min]/[F.max], which return NaN if either argument is NaN, so
   a [top] on either side must stay [top]. Otherwise both are monotone in each
   argument. *)
let min (#{ lo = a; hi = b } as i1 : t) (#{ lo = c; hi = d } as i2 : t) =
  if is_top i1 || is_top i2 then top else make (F.min a c) (F.min b d)
;;

let max (#{ lo = a; hi = b } as i1 : t) (#{ lo = c; hi = d } as i2 : t) =
  if is_top i1 || is_top i2 then top else make (F.max a c) (F.max b d)
;;

let two_pi = Float.pi *. 2.0

(* Absolute padding applied to trig endpoints. The float32 [sin]/[cos] are faithful to
   within a couple of ulps (~2.4e-7 at magnitude 1) but not guaranteed monotone between
   critical points, so a sample inside the interval can land slightly outside the
   endpoint values. *)
let trig_pad = #2e-5s

(* Is there an integer [k] with [lo <= offset + 2k*pi <= hi]? Computed in float64, where
   the conversion from float32 is exact. *)
let has_critical_point ~lo64 ~hi64 ~offset =
  let k_lo = Float.round_up ((lo64 -. offset) /. two_pi) in
  let k_hi = Float.round_down ((hi64 -. offset) /. two_pi) in
  Float.(k_lo <= k_hi)
;;

let trig (f : F.t -> F.t) (#{ lo; hi } as t : t) ~max_offset ~min_offset =
  if is_top t
  then top
  else if not (F.is_finite lo && F.is_finite hi)
  then
    (* sin/cos of an infinity is NaN. *)
    top
  else (
    let lo64 = F.to_float lo
    and hi64 = F.to_float hi in
    if Float.(hi64 -. lo64 >= two_pi)
    then make neg_one one
    else (
      let a = f lo
      and b = f hi in
      let vlo = F.min a b
      and vhi = F.max a b in
      let vlo =
        if has_critical_point ~lo64 ~hi64 ~offset:min_offset
        then neg_one
        else F.max neg_one (F.sub vlo trig_pad)
      in
      let vhi =
        if has_critical_point ~lo64 ~hi64 ~offset:max_offset
        then one
        else F.min one (F.add vhi trig_pad)
      in
      make vlo vhi))
;;

let sin t = trig F.sin t ~max_offset:(Float.pi /. 2.0) ~min_offset:(-.Float.pi /. 2.0)
let cos t = trig F.cos t ~max_offset:0.0 ~min_offset:Float.pi

(* Comparisons use IEEE semantics ([F.O], not [F.compare]): comparisons against NaN are
   false, so [top] operands can never be definite. *)

let lt (#{ lo = a; hi = b } : t) (#{ lo = c; hi = d } : t) : Bool.t =
  if F.O.(b < c)
  then Bool.of_point true
  else if F.O.(a >= d)
  then Bool.of_point false
  else Bool.maybe
;;

let lte (#{ lo = a; hi = b } : t) (#{ lo = c; hi = d } : t) : Bool.t =
  if F.O.(b <= c)
  then Bool.of_point true
  else if F.O.(a > d)
  then Bool.of_point false
  else Bool.maybe
;;

let gt i1 i2 = lt i2 i1
let gte i1 i2 = lte i2 i1
