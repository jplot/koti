.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
{
  .class auto ansi nested public beforefieldinit ServiceDataExt_LueftersteuerungWriteSection
         extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
         implements [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.IWriteableDop1Object
  {
    .method public hidebysig specialname rtspecialname 
            instance void  .ctor(uint8[] data,
                                 int32 offset,
                                 int32 length,
                                 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian endianess) cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldarg.1
      IL_0002:  ldarg.2
      IL_0003:  ldarg.3
      IL_0004:  ldarg.s    endianess
      IL_0006:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_000b:  ldarg.0
      IL_000c:  ldc.i4.1
      IL_000d:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
      IL_0012:  ret
    } // end of method ServiceDataExt_LueftersteuerungWriteSection::.ctor

    .method public hidebysig specialname rtspecialname 
            instance void  .ctor() cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.2
      IL_0002:  newarr     [System.Runtime]System.Byte
      IL_0007:  ldc.i4.0
      IL_0008:  ldc.i4.2
      IL_0009:  ldc.i4.1
      IL_000a:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_000f:  ldarg.0
      IL_0010:  ldc.i4.1
      IL_0011:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
      IL_0016:  ret
    } // end of method ServiceDataExt_LueftersteuerungWriteSection::.ctor

    .method public hidebysig specialname 
            instance class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Enums/VersionEnum 
            get_Struktur_Version() cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.0
      IL_0002:  call       instance uint16 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetU8(int32)
      IL_0007:  ret
    } // end of method ServiceDataExt_LueftersteuerungWriteSection::get_Struktur_Version





            Struktur_Version()
    {
    {
  } // end of class ServiceDataExt_LueftersteuerungWriteSection

  .class auto ansi nested public beforefieldinit ServiceDataExt_LueftersteuerungSection
         extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
  {
    .method public hidebysig specialname rtspecialname 
            instance void  .ctor(uint8[] data,
                                 int32 offset,
                                 int32 length,
                                 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian endianess) cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldarg.1
      IL_0002:  ldarg.2
      IL_0003:  ldarg.3
      IL_0004:  ldarg.s    endianess
      IL_0006:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_000b:  ldarg.0
      IL_000c:  ldc.i4.1
      IL_000d:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
      IL_0012:  ret
    } // end of method ServiceDataExt_LueftersteuerungSection::.ctor

    .method public hidebysig specialname 
            instance class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Enums/VersionEnum 
            get_Struktur_Version() cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.0
      IL_0002:  call       instance uint16 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetU8(int32)
      IL_0007:  ret
    } // end of method ServiceDataExt_LueftersteuerungSection::get_Struktur_Version




    .method public hidebysig specialname 
            instance uint16  get_Luefterstufe() cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.2
      IL_0002:  call       instance uint16 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetU8(int32)
      IL_0007:  ret
    } // end of method ServiceDataExt_LueftersteuerungSection::get_Luefterstufe




            Struktur_Version()
    {
    {
    {
    {
  } // end of class ServiceDataExt_LueftersteuerungSection

  .field private class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection '<ServiceDataExt_LueftersteuerungInstance>k__BackingField'
  .method public hidebysig specialname rtspecialname 
          instance void  .ctor(uint8[] data,
                               int32 offset,
                               int32 length) cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldarg.1
    IL_0002:  ldarg.2
    IL_0003:  ldarg.3
    IL_0004:  ldc.i4.1
    IL_0005:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                 int32,
                                                                                                                                                                                                                 int32,
                                                                                                                                                                                                                 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
    IL_000a:  ldarg.0
    IL_000b:  ldc.i4.1
    IL_000c:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
    IL_0011:  ldarg.0
    IL_0012:  ldarg.1
    IL_0013:  ldc.i4.0
    IL_0014:  ldc.i4.4
    IL_0015:  ldarg.0
    IL_0016:  ldfld      [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::endianess
    IL_001b:  newobj     instance void Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection::.ctor(uint8[],
                                                                                                                                                                              int32,
                                                                                                                                                                              int32,
                                                                                                                                                                              [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
    IL_0020:  call       instance void Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung::set_ServiceDataExt_LueftersteuerungInstance(class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection)
    IL_0025:  ret
  } // end of method ServiceDataExt_Lueftersteuerung::.ctor

  .method public hidebysig specialname static 
          string  get_Dop1ObjectId() cil managed
  {
    .maxstack  8
    IL_0000:  ldstr      "8E01"
    IL_0005:  ret
  } // end of method ServiceDataExt_Lueftersteuerung::get_Dop1ObjectId



  {
          ServiceDataExt_LueftersteuerungInstance()
  {
} // end of class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung
.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Dop2.GLOBAL_PS_Context
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object
{








          UsedSelectionParameter()
  {
          ContextParaHood()
  {
          SelectedBy()
  {
} // end of class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Dop2.GLOBAL_PS_Context

.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
{
  .class auto ansi nested public beforefieldinit Struktur_VersionSection
         extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
  {
    .method public hidebysig specialname rtspecialname 
            instance void  .ctor(uint8[] data,
                                 int32 offset,
                                 int32 length,
                                 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian endianess) cil managed
    {
      // Code size       19 (0x13)
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldarg.1
      IL_0002:  ldarg.2
      IL_0003:  ldarg.3
      IL_0004:  ldarg.s    endianess
      IL_0006:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_000b:  ldarg.0
      IL_000c:  ldc.i4.1
      IL_000d:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
      IL_0012:  ret
    } // end of method Struktur_VersionSection::.ctor

    .method public hidebysig specialname 
            instance class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Enums/VersionEnum 
            get_Version_der_Struktur() cil managed
    {
      // Code size       8 (0x8)
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.0
      IL_0002:  call       instance uint16 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetU8(int32)
      IL_0007:  ret
    } // end of method Struktur_VersionSection::get_Version_der_Struktur
  } // end of class Struktur_VersionSection

  .method public hidebysig specialname static 
          string  get_Dop1ObjectId() cil managed
  {
    // Code size       6 (0x6)
    .maxstack  8
    IL_0000:  ldstr      "1000"
    IL_0005:  ret
  } // end of method DeviceState::get_Dop1ObjectId

  .method public hidebysig specialname rtspecialname 
          instance void  .ctor(uint8[] data,
                               int32 offset,
                               int32 length,
                               [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian endian) cil managed
  {
    // Code size       1335 (0x537)
    .maxstack  5
    IL_0000:  ldarg.0
    IL_0001:  ldarg.1
    IL_0002:  ldarg.2
    IL_0003:  ldarg.3
    IL_0004:  ldarg.s    endian
    IL_0006:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                 int32,
                                                                                                                                                                                                                 int32,
                                                                                                                                                                                                                 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
    IL_000b:  ldarg.0
    IL_000c:  ldc.i4.1
    IL_000d:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::set_UseArrayCopying(bool)
    IL_0012:  ldarg.0
    IL_0013:  ldarg.1
    IL_0014:  ldc.i4.0
    IL_0015:  ldc.i4.1
    IL_0016:  ldarg.0
    IL_0017:  ldfld      [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::endianess
    IL_001c:  newobj     instance void Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState/Struktur_VersionSection::.ctor(uint8[],
                                                                                                                                           int32,
                                                                                                                                           int32,
                                                                                                                                           [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
    IL_0021:  call       instance void Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState::set_Struktur_VersionInstance(class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState/Struktur_VersionSection)
    IL_0536:  ret
  } // end of method DeviceState::.ctor

} // end of class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState

.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ExtendedDopDeviceState
       extends Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState
{
  .method public hidebysig specialname rtspecialname 
          instance void  .ctor(uint8[] data,
                               int32 offset,
                               int32 length) cil managed
  {
    // Code size       11 (0xb)
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldarg.1
    IL_0002:  ldarg.2
    IL_0003:  ldarg.3
    IL_0004:  ldc.i4.1
    IL_0005:  call       instance void Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.DeviceState::.ctor(uint8[],
                                                                                                                   int32,
                                                                                                                   int32,
                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
    IL_000a:  ret
  } // end of method ExtendedDopDeviceState::.ctor

} // end of class Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ExtendedDopDeviceState
