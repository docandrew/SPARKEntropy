--  Keccak-f[1600] permutation and SHAKE-256 sponge
--
--  Standalone implementation for SPARKEntropy.
--  Used for entropy conditioning and XDRBG-256 output generation.

package SPARKEntropy.Keccak with
   SPARK_Mode => On
is
   --  Apply the Keccak-f[1600] permutation (24 rounds)
   procedure Permute (S : in out Keccak_State);

   --  SHAKE-256 operations on the Sponge type

   --  Reset the sponge to initial state
   procedure Reset (Sp : out Sponge)
   with Post => not Sp.Squeezed;

   --  Absorb data into the sponge
   procedure Absorb
     (Sp   : in out Sponge;
      Data : Byte_Seq)
   with Pre  => not Sp.Squeezed
                and Data'Last < Natural'Last,
        Post => not Sp.Squeezed;

   --  Absorb a single U64 value (convenience for time deltas)
   procedure Absorb_U64
     (Sp  : in out Sponge;
      Val : U64)
   with Pre  => not Sp.Squeezed,
        Post => not Sp.Squeezed;

   --  Finalize absorption and switch to squeeze mode.
   --  Applies SHAKE-256 padding (0x1F) and runs permutation.
   procedure Finalize (Sp : in out Sponge)
   with Pre => not Sp.Squeezed,
        Post => Sp.Squeezed;

   --  Squeeze output bytes from the sponge
   procedure Squeeze
     (Sp     : in out Sponge;
      Output : out Byte_Seq)
   with Pre => Sp.Squeezed
               and Output'Last < Natural'Last;

end SPARKEntropy.Keccak;
