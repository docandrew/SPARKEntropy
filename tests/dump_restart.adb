--  Dump entropy in NIST SP 800-90B "row dataset" format for ea_restart.
--
--  ea_restart expects 1000 restarts x 1000 samples each = 1,000,000 bytes.
--  Each row is one restart: we call Init() then Generate() 1000 bytes
--  before tearing the State down and starting over.
--
--  Usage: dump_restart [output_file]   (default: restart.bin)
--         ea_restart -i restart.bin 8 <H_I>
--
--  H_I is the initial entropy estimate from a previous ea_iid /
--  ea_non_iid pass on Generate() output.

with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Command_Line;
with SPARKEntropy;          use SPARKEntropy;

procedure Dump_Restart is
   package SIO renames Ada.Streams.Stream_IO;

   Restarts        : constant := 1000;
   Samples_Per_Row : constant := 1000;

   F : SIO.File_Type;
begin
   declare
      Filename : constant String :=
         (if Ada.Command_Line.Argument_Count >= 1
          then Ada.Command_Line.Argument (1)
          else "restart.bin");
   begin
      SIO.Create (F, SIO.Out_File, Filename);
      Ada.Text_IO.Put_Line ("Restart dump:" & Restarts'Image
                             & " x" & Samples_Per_Row'Image
                             & " ->" & Filename);
   end;

   for R in 1 .. Restarts loop
      declare
         State : Entropy_State;
         OK    : Boolean;
         Buf   : Byte_Seq (0 .. Samples_Per_Row - 1);
         B     : Stream_Element_Array
                   (1 .. Stream_Element_Offset (Samples_Per_Row));
      begin
         Init (State, OK);
         if not OK then
            Ada.Text_IO.Put_Line ("Init FAILED at restart" & R'Image);
            SIO.Close (F);
            return;
         end if;

         Generate (State, Buf, OK);
         if not OK then
            Ada.Text_IO.Put_Line ("Generate FAILED at restart" & R'Image);
            SIO.Close (F);
            return;
         end if;

         for I in Buf'Range loop
            B (Stream_Element_Offset (I) + 1) := Stream_Element (Buf (I));
         end loop;
         SIO.Write (F, B);
      end;

      if R mod 100 = 0 then
         Ada.Text_IO.Put_Line ("  restart" & R'Image & " complete");
      end if;
   end loop;

   SIO.Close (F);
   Ada.Text_IO.Put_Line ("Done: 1,000,000 bytes written");
end Dump_Restart;
