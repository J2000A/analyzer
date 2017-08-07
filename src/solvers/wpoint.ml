(** Top down solver that only keeps values at widening points and restores other values afterwards. *)

open Prelude
open Analyses
open Constraints
open Messages

module WP =
  functor (S:EqConstrSys) ->
  functor (HM:Hash.H with type key = S.v) ->
  struct

    include Generic.SolverStats (S)
    module VS = Set.Make (S.Var)

    module P =
    struct
      type t = S.Var.t * S.Var.t
      let equal (x1,x2) (y1,y2) = S.Var.equal x1 y1 && S.Var.equal x2 y2
      let hash  (x1,x2)         = (S.Var.hash x1 * 13) + S.Var.hash x2
    end

    module HPM = Hashtbl.Make (P)

    let solve box st vs =
      let wpoint = HM.create  10 in
      let stable = HM.create  10 in
      let infl   = HM.create  10 in (* y -> xs *)
      let set    = HM.create  10 in (* y -> xs *)
      let sidevs = HM.create  10 in (* side-effected variables *)
      let called = HM.create  10 in
      let rho    = HM.create  10 in
      let rho'   = HPM.create 10 in (* x,y -> d *)

      let add_infl y x =
        if tracing then trace "sol2" "add_infl %a %a\n" S.Var.pretty_trace y S.Var.pretty_trace x;
        HM.replace infl y (VS.add x (try HM.find infl y with Not_found -> VS.empty))
      in
      let add_set x y d =
        HM.replace set y (VS.add x (try HM.find set y with Not_found -> VS.empty));
        HPM.add rho' (x,y) d;
        HM.replace sidevs y ()
      in
      let is_side x = HM.mem set x in
      let make_wpoint x =
        if tracing then trace "sol2" "make_wpoint %a on %i\n" S.Var.pretty_trace x (S.Var.line_nr x);
        HM.replace wpoint x ()
      in
      let rec destabilize x =
        if tracing then trace "sol2" "destabilize %a on %i\n" S.Var.pretty_trace x (S.Var.line_nr x);
        let w = HM.find_default infl x VS.empty in
        HM.replace infl x VS.empty;
        VS.iter (fun y -> HM.remove stable y; destabilize y) w
      and solve x =
        if tracing then trace "sol2" "solve %a on %i, called: %b, stable: %b\n" S.Var.pretty_trace x (S.Var.line_nr x) (HM.mem called x) (HM.mem stable x);
        if not (HM.mem called x || HM.mem stable x) then begin
          HM.replace stable x ();
          HM.replace called x ();
          let wpx = HM.mem wpoint x in
          HM.remove wpoint x;
          let old = HM.find rho x in
          let l = HM.create 10 in
          let effects = ref Set.empty in
          let tmp = eq x (eval l effects x) (side x) effects in
          let tmp = S.Dom.join tmp (sides x) in
          if tracing then trace "sol" "Var: %a\n" S.Var.pretty_trace x ;
          if tracing then trace "sol" "Contrib:%a\n" S.Dom.pretty tmp;
          let tmp = if is_side x then S.Dom.widen old (S.Dom.join old tmp) else if wpx then box x old tmp else tmp in
          HM.remove called x;
          if not (S.Dom.equal old tmp) then begin
            if tracing then if is_side x then trace "sol2" "solve side: old = %a, tmp = %a, widen = %a\n" S.Dom.pretty old S.Dom.pretty tmp S.Dom.pretty (S.Dom.widen old (S.Dom.join old tmp));
            update_var_event x old tmp;
            if tracing then trace "sol" "New Value:%a\n\n" S.Dom.pretty tmp;
            if tracing then trace "sol2" "new value for %a (wpx: %b, is_side: %b) on %i is %a. Old value was %a\n" S.Var.pretty_trace x wpx (is_side x) (S.Var.line_nr x) S.Dom.pretty tmp S.Dom.pretty old;
            HM.replace rho x tmp;
            destabilize x;
            (solve[@tailcall]) x;
          end;
        end;
      and eq x get set effects =
        if tracing then trace "sol2" "eq %a on %i\n" S.Var.pretty_trace x (S.Var.line_nr x);
        eval_rhs_event x;
        match S.system x with
        | None -> S.Dom.bot ()
        | Some f ->
          let sidef y d =
            if not (Set.mem y !effects) then (
              HPM.replace rho' (x,y) (S.Dom.bot ());
              effects := Set.add y !effects
            );
            set y d
          in
          f get sidef
      and eval l effects x y =
        if tracing then trace "sol2" "eval %a on %i ## %a on %i\n" S.Var.pretty_trace x (S.Var.line_nr x) S.Var.pretty_trace y (S.Var.line_nr y);
        get_var_event y;
        if HM.mem called y then (make_wpoint y; init y);
        if HM.mem rho y then (
          if neg is_side y then solve y;
          add_infl y x;
          HM.find rho y
        )
        else if HM.mem l y then HM.find l y
        else (
          HM.replace called y ();
          let d = eq y (eval l effects x) (side x) effects in
          HM.remove called y;
          if HM.mem wpoint y then (
            solve y;
            add_infl y x;
            HM.find rho y
          ) else (
            HM.replace l y d;
            d
          )
        )
      and sides x =
        let w = try HM.find set x with Not_found -> VS.empty in
        let d = Enum.fold (fun d y -> let r = try S.Dom.join d (HPM.find rho' (y,x)) with Not_found -> d in if tracing then trace "sol2" "sides: side %a from %a: %a\n" S.Var.pretty_trace x S.Var.pretty_trace y S.Dom.pretty r; r) (S.Dom.bot ()) (VS.enum w) in
        if tracing then trace "sol2" "sides %a on %i ## %a\n" S.Var.pretty_trace x (S.Var.line_nr x) S.Dom.pretty d;
        d
      and side x y d =
        if S.Dom.is_bot d then () else
        if tracing then trace "sol2" "side %a on %i ## %a on %i (wpx: %b) ## %a\n" S.Var.pretty_trace x  (S.Var.line_nr x) S.Var.pretty_trace y (S.Var.line_nr y) (HM.mem wpoint y) S.Dom.pretty d;
        if not (HM.mem rho y) then begin
          init y;
          add_set x y d;
          solve y
        end else begin
          let old = try HPM.find rho' (x,y) with Not_found -> S.Dom.bot () in
          if not (S.Dom.equal old d) then begin
            add_set x y (S.Dom.join old d);
            HM.remove stable y;
            solve y;
          end
        end
      and init x =
        if tracing then trace "sol2" "init %a on %i\n" S.Var.pretty_trace x (S.Var.line_nr x);
        if not (HM.mem rho x) then begin
          new_var_event x;
          HM.replace rho  x (S.Dom.bot ());
          HM.replace infl x (VS.add x VS.empty)
        end
      in

      let set_start (x,d) =
        if tracing then trace "sol2" "set_start %a on %i ## %a\n" S.Var.pretty_trace x  (S.Var.line_nr x) S.Dom.pretty d;
        init x;
        add_set x x d;
        solve x
      in

      start_event ();
      List.iter set_start st;
      List.iter init vs;
      List.iter solve vs;
      let keys h = HM.fold (fun k _ a -> k::a) h [] in
      let n = ref 1 in
      (* iterate until there are no more new side-effects *)
      let rec solve_sidevs () =
        let gs = keys sidevs in
        HM.clear sidevs;
        if gs <> [] then (
          if tracing then trace "sol2" "Round %d: %d side-effected variables to solve\n" !n (List.length gs);
          incr n;
          List.iter solve gs;
          List.iter solve vs;
          solve_sidevs ()
        )
      in
      solve_sidevs ();

      (* verifies values at widening points and adds values for variables in-between *)
      let visited = HM.create 10 in
      let rec get x =
        if HM.mem visited x then
          HM.find rho x
        else (
          HM.replace visited x ();
          let check_side y d =
            let d' = try HM.find rho y with Not_found -> S.Dom.bot () in
            if not (S.Dom.leq d d') then ignore @@ Pretty.printf "Fixpoint not reached in restore step at side-effected variable %a: %a not leq %a\n" S.Var.pretty_trace y S.Dom.pretty d S.Dom.pretty d'
          in
          let eq x =
            match S.system x with
            | None -> if HM.mem rho x then HM.find rho x else S.Dom.bot ()
            | Some f -> f get check_side
          in
          if HM.mem rho x then (
            let d1 = HM.find rho x in
            let d2 = eq x in
            if not (S.Dom.leq d2 d1) then
              ignore @@ Pretty.printf "Fixpoint not reached in restore step at %a (%s:%d)\n  @[Variable:\n%a\nRight-Hand-Side:\n%a\nCalculating one more step changes: %a\n@]" S.Var.pretty_trace x (S.Var.file_name x) (S.Var.line_nr x) S.Dom.pretty d1 S.Dom.pretty d2 S.Dom.pretty_diff (d1,d2);
            d1
          ) else (
            let d = eq x in
            HM.replace rho x d;
            d
          )
        )
      in
      (* restore values for non-widening-points *)
      if GobConfig.get_bool "exp.solver.wp.restore" then (
        if (GobConfig.get_bool "dbg.verbose") then
          print_endline ("Restoring missing values.");
        let restore () = ignore @@ List.map get vs in
        Stats.time "restore" restore ();
        ignore @@ Pretty.printf "Solved %d vars. Total of %d vars after restore.\n" !Goblintutil.vars (HM.length rho);
      );

      let reachability xs =
        let reachable = HM.create (HM.length rho) in
        let rec one_var x =
          if not (HM.mem reachable x) then begin
            HM.replace reachable x ();
            match S.system x with
            | None -> ()
            | Some x -> one_constaint x
          end
        and one_constaint f =
          ignore (f (fun x -> one_var x; try HM.find rho x with Not_found -> S.Dom.bot ()) (fun x _ -> one_var x))
        in
        List.iter one_var xs;
        HM.iter (fun x _ -> if not (HM.mem reachable x) then HM.remove rho x) rho
      in
      reachability vs;
      stop_event ();

      HM.clear wpoint;
      HM.clear stable;
      HM.clear infl  ;
      HM.clear set   ;
      HPM.clear rho'  ;

      rho

  end

let _ =
  let module WP = GlobSolverFromIneqSolver (SLR.JoinContr (WP)) in
  Selector.add_solver ("wpoint", (module WP : GenericGlobSolver));