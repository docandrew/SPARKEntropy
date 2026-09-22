--  Record raw time deltas for the NIST SP 800-90B assessment of the
--  noise source, the way jitterentropy's jitterentropy-hashtime does for
--  its ESV validation: every sample is the delta Noise.Measure_Jitter
--  returns (after division by the timer GCD), with the stuck indicator
--  disregarded, before any conditioning.
--
--  Usage: dump_raw <events> <repeats> <out_prefix> [--counter-ticks]
--
--    runtime data:  dump_raw 1000000 1    raw-runtime
--    restart data:  dump_raw 1000    1000 raw-restart
--
--  Deltas are recorded in raw timer ticks: the timer GCD that Init
--  measured (43 on a Zen 5 TSC, for instance) is set to 1 for the
--  recording, as jitterentropy-hashtime does ("we want the raw values,
--  not values that have had common factors removed"). The generator
--  itself absorbs GCD-divided deltas; --counter-ticks records those
--  instead (hashtime's --report-counter-ticks).
--
--  Each repeat is a fresh Entropy_State: Init (power-up test, GCD)
--  and then <events> deltas. Repeats are written back to back, so the
--  restart file is the SP 800-90B 3.1.4 row dataset (one restart per
--  row of <events> samples). Two files are written:
--
--    <out_prefix>.u64   every delta as 8 little-endian bytes
--    <out_prefix>.lsb8  the low 8 bits of every delta, one byte each
--                       (jitterentropy's extractlsb with mask FF:8; this
--                       is what ea_non_iid / ea_restart read with
--                       symbol size 8)
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;            use Interfaces;
with SPARKEntropy;          use SPARKEntropy;
with SPARKEntropy.Noise;

procedure Dump_Raw is
   package SIO renames Ada.Streams.Stream_IO;

   Events  : Natural;
   Repeats : Natural;
   F64, F8 : SIO.File_Type;
   Stuck_Total : Natural := 0;
   Counter_Ticks : Boolean := False;
begin
   if Ada.Command_Line.Argument_Count = 4
     and then Ada.Command_Line.Argument (4) = "--counter-ticks"
   then
      Counter_Ticks := True;
   elsif Ada.Command_Line.Argument_Count /= 3 then
      Ada.Text_IO.Put_Line ("usage: dump_raw <events> <repeats> <out_prefix> [--counter-ticks]");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;
   Events  := Natural'Value (Ada.Command_Line.Argument (1));
   Repeats := Natural'Value (Ada.Command_Line.Argument (2));
   declare
      Prefix : constant String := Ada.Command_Line.Argument (3);
   begin
      SIO.Create (F64, SIO.Out_File, Prefix & ".u64");
      SIO.Create (F8,  SIO.Out_File, Prefix & ".lsb8");
      Ada.Text_IO.Put_Line ("SPARKEntropy raw deltas:" & Repeats'Image & " x"
                            & Events'Image & " ->" & Prefix & ".u64 / .lsb8");
   end;

   for R in 1 .. Repeats loop
      declare
         State : Entropy_State;
         OK    : Boolean;
         Dt    : U64;
         Stuck : Boolean;
         --  Deltas are written in chunks. A file write between two calls
         --  cannot touch a sample: each delta is taken between the two
         --  timer reads inside Measure_Jitter.
         Chunk : constant := 4096;
         Buf64 : Stream_Element_Array (1 .. Chunk * 8);
         Buf8  : Stream_Element_Array (1 .. Chunk);
         Fill  : Natural := 0;
      begin
         Init (State, OK);
         if not OK then
            Ada.Text_IO.Put_Line ("Init FAILED at repeat" & R'Image
                                  & " (timer unsuitable or health test)");
            SIO.Close (F64); SIO.Close (F8);
            Ada.Command_Line.Set_Exit_Status (1);
            return;
         end if;
         if R = 1 then
            Ada.Text_IO.Put_Line ("timer GCD measured by Init:" & State.Timer_GCD'Image
                                  & ", OSR" & State.OSR'Image
                                  & (if Counter_Ticks then "; recording GCD-divided deltas"
                                     else "; recording raw timer ticks (GCD set to 1)"));
         end if;
         if not Counter_Ticks then
            State.Timer_GCD := 1;
         end if;

         for I in 1 .. Events loop
            Noise.Measure_Jitter (State, Dt, Stuck);
            if Stuck then
               Stuck_Total := Stuck_Total + 1;
            end if;
            Fill := Fill + 1;
            Buf8 (Stream_Element_Offset (Fill)) := Stream_Element (Dt and 16#FF#);
            declare
               V : U64 := Dt;
            begin
               for B in 0 .. 7 loop
                  Buf64 (Stream_Element_Offset (Fill - 1) * 8 + Stream_Element_Offset (B) + 1) :=
                    Stream_Element (V and 16#FF#);
                  V := Shift_Right (V, 8);
               end loop;
            end;
            if Fill = Chunk or else I = Events then
               SIO.Write (F64, Buf64 (1 .. Stream_Element_Offset (Fill) * 8));
               SIO.Write (F8,  Buf8  (1 .. Stream_Element_Offset (Fill)));
               Fill := 0;
            end if;
         end loop;
      end;
      if Repeats > 1 and then R mod 100 = 0 then
         Ada.Text_IO.Put_Line ("  repeat" & R'Image & " complete");
      end if;
   end loop;

   SIO.Close (F64); SIO.Close (F8);
   Ada.Text_IO.Put_Line ("Done:" & Natural'Image (Events * Repeats) & " deltas,"
                         & Stuck_Total'Image & " flagged stuck (recorded anyway)");
end Dump_Raw;
