template <typename Str_Array>
void Inverse (Str_Array Input, Str_Array Output){
  Str_Array Result;
  int Index;

  for (Index = 0; Index < sizeof (Str_Array); Index ++) {
    Result[Index] = Input[sizeof (Str_Array) - 1 - Index];
  }

  for (Index = 0; Index < sizeof (Str_Array); Index ++) {
    Output[Index] = Result[Index];
  }
}

typedef char Data_Type[5];

Data_Type Data = {'a', 'b', 'c', 'd', 'e'};
Data_Type Result;

int main (void) {
  Inverse<Data_Type>(Data, Result);
  return 0;
}
