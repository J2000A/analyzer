// PARAM: --debug --with var_eq
#include<stdio.h>
#include<assert.h>

int main() {
  int x;
  int y;

  scanf("%d", &x);
  y = x;

  assert(x==y);

  return 0;
}
