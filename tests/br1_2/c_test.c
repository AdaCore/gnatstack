
void fill_string (char* str, int length) {
   int i;
   for (i=0; i<=length-1; i++) {
      str[i] = 'x';
   }
}
   

int main () {
   char* str;
   int length = 100;

   fill_string (str, length);
}
