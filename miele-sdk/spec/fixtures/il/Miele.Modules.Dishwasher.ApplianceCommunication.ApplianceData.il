.class public auto ansi beforefieldinit Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
{
  .class auto ansi nested public beforefieldinit SettingsWriteSection
         extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object
         implements [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.IWriteableDop1Object
  {
    .interfaceimpl type [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.IWriteableDop1Object

    .field private class Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField '<Extras_BitFieldInstance>k__BackingField'
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
      IL_000c:  ldarg.0
      IL_000d:  call       instance uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::get_Dop1Data()
      IL_0012:  ldc.i4.2
      IL_0013:  ldc.i4.2
      IL_0014:  ldarg.s    endianess
      IL_0016:  newobj     instance void Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField::.ctor(uint8[],
                                                                                                                                                                                               int32,
                                                                                                                                                                                               int32,
                                                                                                                                                                                               [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_001b:  call       instance void Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection::set_Extras_BitFieldInstance(class Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField)
      IL_0020:  ret
    } // end of method SettingsWriteSection::.ctor

    .method public hidebysig specialname rtspecialname 
            instance void  .ctor() cil managed
    {
      .maxstack  8
      IL_0000:  ldarg.0
      IL_0001:  ldc.i4.4
      IL_0002:  newarr     [System.Runtime]System.Byte
      IL_0007:  ldc.i4.0
      IL_0008:  ldc.i4.4
      IL_0009:  ldc.i4.0
      IL_000a:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::.ctor(uint8[],
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   int32,
                                                                                                                                                                                                                   [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_000f:  ldarg.0
      IL_0010:  ldarg.0
      IL_0011:  call       instance uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::get_Dop1Data()
      IL_0016:  ldc.i4.2
      IL_0017:  ldc.i4.2
      IL_0018:  ldarg.0
      IL_0019:  ldfld      [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::endianess
      IL_001e:  newobj     instance void Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField::.ctor(uint8[],
                                                                                                                                                                                               int32,
                                                                                                                                                                                               int32,
                                                                                                                                                                                               [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object/Endian)
      IL_0023:  call       instance void Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection::set_Extras_BitFieldInstance(class Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField)
      IL_0028:  ret
    } // end of method SettingsWriteSection::.ctor
    .method public hidebysig newslot virtual final 
            instance uint8[]  GenerateWriteBytes() cil managed
    {
      .maxstack  4
      .locals init ([System.Collections]System.Collections.Generic.List`1<uint8> V_0)
      IL_0000:  newobj     instance void [System.Collections]System.Collections.Generic.List`1<uint8>::.ctor()
      IL_0005:  stloc.0
      IL_0006:  ldloc.0
      IL_0007:  ldarg.0
      IL_0008:  call       instance uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetData()
      IL_000d:  ldc.i4.0
      IL_000e:  ldc.i4.1
      IL_000f:  call       uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1ByteArrayConverter::GetSubArray(uint8[],
                                                                                                                                                                                                                               int32,
                                                                                                                                                                                                                               int32)
      IL_0014:  callvirt   instance void [System.Collections]System.Collections.Generic.List`1<uint8>::AddRange([System.Runtime]System.Collections.Generic.IEnumerable`1<!0>)
      IL_0019:  ldloc.0
      IL_001a:  ldarg.0
      IL_001b:  call       instance uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetData()
      IL_0020:  ldc.i4.1
      IL_0021:  ldc.i4.1
      IL_0022:  call       uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1ByteArrayConverter::GetSubArray(uint8[],
                                                                                                                                                                                                                               int32,
                                                                                                                                                                                                                               int32)
      IL_0027:  callvirt   instance void [System.Collections]System.Collections.Generic.List`1<uint8>::AddRange([System.Runtime]System.Collections.Generic.IEnumerable`1<!0>)
      IL_002c:  ldloc.0
      IL_002d:  ldarg.0
      IL_002e:  call       instance class Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection/Extras_BitField Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection::get_Extras_BitFieldInstance()
      IL_0033:  callvirt   instance uint8[] [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object::GetData()
      IL_0038:  callvirt   instance void [System.Collections]System.Collections.Generic.List`1<uint8>::AddRange([System.Runtime]System.Collections.Generic.IEnumerable`1<!0>)
      IL_003d:  ldloc.0
      IL_003e:  callvirt   instance !0[] [System.Collections]System.Collections.Generic.List`1<uint8>::ToArray()
      IL_0043:  ret
    } // end of method SettingsWriteSection::GenerateWriteBytes
  } // end of class SettingsWriteSection
} // end of class Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.SmartControl_GSD_Programmwahl_Setzen
