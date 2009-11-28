#include "data_handling.h"

int main (void) {
  typedef char My_Str[5];

  /*
  typedef Data_Type<My_Str> Container;

  Container Data('a');
  */

  Data_Type <My_Str> Data ('a');

  Data.Inverse ();

  return 0;
}
