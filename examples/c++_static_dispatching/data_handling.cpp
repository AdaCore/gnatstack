#include "data_handling.h"

Data_Type::Data_Type (int a, int b, int c, int d, int e) {
  Contents[0] = a;
  Contents[1] = b;
  Contents[2] = c;
  Contents[3] = d;
  Contents[4] = e;
}

void Data_Type::Inverse (void)
{
  int Tmp[5];
  int Index;
  
  for (Index = 0; Index < 5; Index ++) {
    Tmp[Index] = Contents[4 - Index];
  }
  
  for (Index = 0; Index < 5; Index ++) {
    Contents[Index] = Tmp[Index];
  } 
}
