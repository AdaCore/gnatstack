template <class Str_Array>
class Data_Type {
  Str_Array Contents;
 public:
  Data_Type (char first_char);
  virtual void Inverse (void);
};

template <class Str_Array>
Data_Type<Str_Array>::Data_Type (char first_char) {
  int Index;
  char Value = first_char;

  for (Index = 0; Index < sizeof (Str_Array); Index ++) {
    Contents[Index] = Value;
    Value ++;
  }
}

template <class Str_Array>
void Data_Type<Str_Array>::Inverse (void)
{
  Str_Array Tmp;
  int Index;

  for (Index = 0; Index < sizeof (Str_Array); Index ++) {
    Tmp[Index] = Contents[sizeof (Str_Array) - 1 - Index];
  }

  for (Index = 0; Index < sizeof (Str_Array); Index ++) {
    Contents[Index] = Tmp[Index];
  }
}
