    .class auto ansi nested public beforefieldinit Info_Kochstelle_Kochstelle_1
           extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Bitfield
    {









      .method public hidebysig specialname 
              instance class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/ActiveEnum 
              'get_Topfgroeße_erkannt_Variokochzone_1'() cil managed
      {
        .maxstack  8
        IL_0000:  ldarg.0
        IL_0001:  ldc.i4.4
        IL_0002:  ldc.i4.1
        IL_0003:  call       instance int32 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Bitfield::GetBitValue(int32,
                                                                                                                                                                                                                              int32)
        IL_0008:  ret
      } // end of method Info_Kochstelle_Kochstelle_1::'get_Topfgroeße_erkannt_Variokochzone_1'

      .method public hidebysig specialname 
              instance void  'set_Topfgroeße_erkannt_Variokochzone_1'(class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/ActiveEnum 'value') cil managed
      {
        .maxstack  8
        IL_0000:  ldarg.0
        IL_0001:  ldc.i4.4
        IL_0002:  ldc.i4.1
        IL_0003:  ldarg.1
        IL_0004:  call       instance void [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Bitfield::SetBits(int32,
                                                                                                                                                                                                                         int32,
                                                                                                                                                                                                                         int32)
        IL_0009:  ret
      } // end of method Info_Kochstelle_Kochstelle_1::'set_Topfgroeße_erkannt_Variokochzone_1'





              Ankochautomatik()
      {
              Variozone_1()
      {
              Variozone_2()
      {
              Topf_erkannt()
      {
              'Topfgroeße_erkannt_Variokochzone_1'()
      {
              'Topfgroeße_erkannt_Variokochzone_2'()
      {
              Boosterfunktion()
      {
    } // end of class Info_Kochstelle_Kochstelle_1

    .class auto ansi nested public beforefieldinit Kochstelle_1
           extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Bitfield
    {







      .method public hidebysig specialname 
              instance class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/'BestätigungNotwendigEnum' 
              get_Bestaetigung_notwendig() cil managed
      {
        .maxstack  8
        IL_0000:  ldarg.0
        IL_0001:  ldc.i4.6
        IL_0002:  ldc.i4.1
        IL_0003:  call       instance int32 [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Bitfield::GetBitValue(int32,
                                                                                                                                                                                                                              int32)
        IL_0008:  ret
      } // end of method Kochstelle_1::get_Bestaetigung_notwendig




              Benutzereinstellung()
      {
              Zieltemperatur()
      {
              Konflikt()
      {
              Bestaetigung_notwendig()
      {
              Spulenkonflikt()
      {
    } // end of class Kochstelle_1

.class public auto ansi beforefieldinit Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums
       extends [System.Runtime]System.Object
{
  .class auto ansi sealed nested public 'BestätigungNotwendigEnum'
         extends [System.Runtime]System.Enum
  {
    .field public specialname rtspecialname int32 value__
    .field public static literal class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/'BestätigungNotwendigEnum' keine_Bestaetigung_notwendig = int32(0x00000000)
    .field public static literal class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/'BestätigungNotwendigEnum' Bestaetigung_notwendig = int32(0x00000001)
  } // end of class 'BestätigungNotwendigEnum'
} // end of class Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums
