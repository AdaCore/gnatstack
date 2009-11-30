#include "data_handling.h"

void Inverse (Data_Type Input, Data_Type Output){
  Data_Type Result;
  int Index;

  for (Index = 0; Index < 5; Index ++) {
    Result[Index] = Input[4 - Index];
  }
  
  for (Index = 0; Index < 5; Index ++) {
    Output[Index] = Result[Index];
  } 
}

void External_Inverse (Data_Type Input, Data_Type Output){
  Inverse (Input, Output);
}
