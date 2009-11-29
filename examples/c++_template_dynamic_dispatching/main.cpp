#include "data_handling.h"

int main (void) {
  typedef char My_Str[5];

  Data_Type <My_Str> Data ('a');
  Data_Type <My_Str> *Ptr = &Data;

  Ptr->Inverse ();

  return 0;
}
