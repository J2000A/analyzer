//PARAM: --set ana.activated "['base','threadid','threadflag','escape','fmode', 'OSEK', 'OSEK2', 'stack_trace_set','mallocWrapper']" --sets ana.osek.oil 07-flags.oil --sets ana.osek.flags[+] flag

int flag = 0;
int var = 0;

ISR(high)
{
  GetResource(r);
  ReleaseResource(r);
}

ISR(two)
{
  if (flag == 0) {
    var ++; //RACE
  }
}

ISR(four)
{
  flag = 1;
  int temp = var;
  var = temp - var;
//   assert(var = 0);      //
  flag = 0;
}

TASK(init)
{
  GetResource(r);
  var = 0;
  flag = 0;
  ReleaseResource(r);
}
