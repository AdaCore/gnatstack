typedef int Data_Type[5];

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

Data_Type Data = {1, 2, 3, 4, 5};
Data_Type Result;

int main (void) {
  Inverse (Data, Result);
  return 0;
}
