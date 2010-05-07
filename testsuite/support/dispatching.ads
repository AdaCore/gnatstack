
package Dispatching is
   type Base is tagged null record;
   procedure Foo (X : Base);

   type Base_CA is access all Base'Class;

   type Intermediate is new Base with null record;

   type Intermediate_CA is access all Intermediate'Class;

   type Derived is new Intermediate with null record;
   procedure Foo (X : Derived);

   type Derived_CA is access all Derived'Class;

   type Subderived is new Derived with null record;
   procedure Foo (X : Subderived);

   type Subderived_CA is access all Subderived'Class;

   Buffer_10    : array (1 .. 10)    of Integer := (others => 10);
   Buffer_100   : array (1 .. 100)   of Integer := (others => 10);
   Buffer_1000  : array (1 .. 1000)  of Integer := (others => 10);
end Dispatching;
