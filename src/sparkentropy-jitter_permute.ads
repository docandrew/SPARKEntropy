--  Keccak-f[1600] permutation — used ONLY for entropy timing jitter.
--
--  All cryptographic SHAKE-256 operations now go through the
--  proven libkeccak (damaki/libkeccak) Alire crate. The raw
--  permutation is kept here because libkeccak does not expose
--  Permute publicly, and noise.adb's Hash_Loop uses it as a
--  variable-execution-time CPU stressor for entropy gathering
--  (NOT for cryptographic correctness).
--
--  Renamed from SPARKEntropy.Keccak to SPARKEntropy.Jitter_Permute
--  so it doesn't shadow libkeccak's root Keccak package in
--  child-package bodies that need both.

package SPARKEntropy.Jitter_Permute with
   SPARK_Mode => On
is
   --  Apply the Keccak-f[1600] permutation (24 rounds) in place.
   procedure Permute (S : in out Keccak_State);

end SPARKEntropy.Jitter_Permute;
