
open Cil
open Pretty
open Analyses
open DeadlockDomain
open Printf

let forbiddenList : ( (myowntypeEntry*myowntypeEntry) list ref) = ref []

let equalLock x y = 
  ValueDomain.Addr.equal (x.addr) (y.addr)

let addLock (newLock,lock) lockList =
  if (List.exists (fun (a,b) -> ((equalLock a newLock) && (equalLock b lock)) ) lockList) then ()
  else forbiddenList := (newLock,lock)::!forbiddenList

let addLockingInfo newLock lockList =
  (* Add newLock to availableLocks *)
  if (List.exists (fun x -> ValueDomain.Addr.equal (x.addr) (newLock.addr)) !availableLocks) = false then availableLocks := newLock::!availableLocks else ();

  (* Check forbidden list *)
  List.iter (fun e -> List.iter (fun (a,b) -> 
      if ((equalLock a e) && (equalLock b newLock)) then (
        let msg = (sprintf "Deadlock warning: Locking order %s, %s in line %i, %i (after %i, %i)\n" (ValueDomain.Addr.short () e.addr) (ValueDomain.Addr.short () newLock.addr) e.loc.line newLock.loc.line b.loc.line a.loc.line) in
        Messages.report msg;
      )
      else () ) !forbiddenList ) lockList;

  (* Add forbidden order *)
  List.iter (
    fun lock -> 
      forbiddenList := (newLock,lock)::!forbiddenList;
      let transAddList = List.find_all (fun (a,b) -> equalLock a lock) !forbiddenList in
      List.iter (fun (a,b) -> forbiddenList := (newLock,b)::!forbiddenList ) transAddList
  ) lockList;
  ()

module Spec =
struct
  include Analyses.DefaultSpec

  let name = "deadlock"

  (* The domain for the analysis *)
  module D = DeadlockDomain.Lockset
  module C = DeadlockDomain.Lockset
  module G = Lattice.Unit

  (* Initialization and finalization *)
  let init () = ()

  let finalize () = ()

  (* Some required states *)
  let startstate _ : D.t = D.empty ()
  let otherstate _ : D.t = D.empty ()
  let exitstate  _ : D.t = D.empty ()
  
  (* ======== Transfer functions ======== *)
  (* Called for assignments, branches, ... *)

  (* Assignment lval <- exp *)
  let assign ctx (lval:lval) (rval:exp) : D.t =
    ctx.local
   
  (* Branch *)
  let branch ctx (exp:exp) (tv:bool) : D.t = 
    ctx.local
  
  (* Body of a function starts *)
  let body ctx (f:fundec) : D.t = 
     ctx.local

  (* Returns from a function *)
  let return ctx (exp:exp option) (f:fundec) : D.t = 
    ctx.local
  
  (* Calls/Enters a function *)
  let enter ctx (lval: lval option) (f:varinfo) (args:exp list) : (D.t * D.t) list =
    [[],ctx.local]
  
  (* Leaves a function *)
  let combine ctx (lval:lval option) fexp (f:varinfo) (args:exp list) (au:D.t) : D.t =
    au

  (* Helper function to convert query-offsets to valuedomain-offsets *)
  let rec conv_offset x =
    match x with
      | `NoOffset    -> `NoOffset
      | `Index (Const (CInt64 (i,_,_)),o) -> `Index (ValueDomain.IndexDomain.of_int i, conv_offset o)
      | `Index (_,o) -> `Index (ValueDomain.IndexDomain.top (), conv_offset o)
      | `Field (f,o) -> `Field (f, conv_offset o)

  (* Query the value (of the locking argument) to a list of locks. *)
  let eval_exp_addr a exp =
    let gather_addr (v,o) b = ValueDomain.Addr.from_var_offset (v,conv_offset o) :: b in
    match a (Queries.MayPointTo exp) with
      | `LvalSet a when not (Queries.LS.is_top a) -> 
          Queries.LS.fold gather_addr (Queries.LS.remove (dummyFunDec.svar, `NoOffset) a) []    
      | `Bot -> []
      | b -> Messages.warn ("Could not evaluate '"^sprint 30 (d_exp () exp)^"' to an points-to set, instead got '"^Queries.Result.short 60 b^"'."); []
    
  (* Called when calling a special/unknown function *)
  let special ctx (lval: lval option) (f:varinfo) (arglist:exp list) : D.t =
    match LibraryFunctions.classify f.vname arglist with
      | `Lock (_, _) ->  
          begin match eval_exp_addr ctx.ask (List.hd arglist) with
            | [lockAddr] ->             
              addLockingInfo {addr = lockAddr; loc = !Tracing.current_loc } ctx.local;
              {addr = lockAddr; loc = !Tracing.current_loc }::ctx.local
            | _ -> ctx.local
          end
  
      | `Unlock -> 
           let lockAddrs = eval_exp_addr ctx.ask (List.hd arglist) in
           let inLockAddrs e = List.exists (fun r -> ValueDomain.Addr.equal r e.addr) lockAddrs in
           List.filter inLockAddrs ctx.local
        
      | _ -> ctx.local

end

let _ = 
  MCP.register_analysis (module Spec : Spec)         
