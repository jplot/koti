.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_SelectionParaCA
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object
{









  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Dop2_U16,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_Temperature() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.6
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetGeneratedObject<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Dop2_U16>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_SelectionParaCA::get_Temperature


















































          GrillLevel()
  {
          Moisture()
  {
          Level()
  {
          Temperature()
  {
          CoreTemperature()
  {
          StartBurstOfSteam1()
  {
          StartBurstOfSteam2()
  {
          StartBurstOfSteam3()
  {
          Weight()
  {
          Duration()
  {
          StartAt()
  {
          EndAt()
  {
          MwPower()
  {
          RfIntensity()
  {
          RfEnergyQuantity()
  {
          NumberOfSteamBursts()
  {
          ShowCalculatedRemainingTime()
  {
          UseRapidHeating()
  {
          SetDoorLock()
  {
          UseRotisserie()
  {
          UsePreHeating()
  {
          UseCrispFunction()
  {
          UseRapidCooling()
  {
          UseHolding()
  {
          MenuCookingProg()
  {
          ProgramExtend()
  {
          Browning()
  {
          Doneness()
  {
} // end of class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_SelectionParaCA
.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_Select
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object
{



  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumPrgId,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_ProgId() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.1
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetEnum<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumPrgId>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_Select::get_ProgId




  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_SelectionType() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.3
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetEnum<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_Select::get_SelectionType





  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_SelectionParaCA,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_SelectionParaCA() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.7
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetGeneratedObject<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_SelectionParaCA>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_Select::get_SelectionParaCA




          ProgId()
  {
          SelectionParameter()
  {
          SelectionType()
  {
          SelectionParaDW()
  {
          SelectionParaTD()
  {
          SelectionParaWM()
  {
          SelectionParaCA()
  {
          SelectionParaCO()
  {
          SelectionParaPW()
  {
          SelectionParaHood()
  {
} // end of class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_Select
.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_AttributesCCA
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object
{









  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_GenericParameterValueReadOnlyU16,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_TotalRemainingTime() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.5
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetGeneratedObject<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_GenericParameterValueReadOnlyU16>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_AttributesCCA::get_TotalRemainingTime

  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_GenericParameterValueReadOnlyU8,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_Level() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.5
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetGeneratedObject<class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_GenericParameterValueReadOnlyU8>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_PS_AttributesCCA::get_Level




























          ProgPhase()
  {
          ProgSubPhase()
  {
          ProgressBar()
  {
          StepRemainingTime()
  {
          TotalRemainingTime()
  {
          Level()
  {
          DisplayTemperature()
  {
          DisplayCoreTemperature()
  {
          RapidHeating()
  {
          DisplayMoisture()
  {
          Programtype()
  {
          ProgPhaseChange()
  {
          RemainingSteamBursts()
  {
          CurrentProgramStep()
  {
          TotalProgramSteps()
  {
          ContinueCooking()
  {
          RfEnergyQuantity()
  {
          BitField()
  {
          StepsOperationMode()
  {
          TemperatureSetpoint()
  {
          MoistureSetpoint()
  {
          CoreTemperatureSetpoint()
  {
          PowerMwSetpoint()
  {
          GrillLevelSetpoint()
  {
          PointInTimeOfStart()
  {
          ProgId()
  {
          PointInTimeOfNextAction()
  {
} // end of class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_PS_AttributesCCA
.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA
       extends [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object
{



  .method public hidebysig specialname instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Dop2_U8,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> 
          get_AmountOfSteps() cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4.1
    IL_0002:  call       instance [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Either`2<!!0,[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Base.Dop2Error> [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object::GetGeneratedObject<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Attributes.Dop2_U8>(uint16)
    IL_0007:  ret
  } // end of method GLOBAL_OP_ProgramInfoCA::get_AmountOfSteps












          AmountOfSteps()
  {
          CurrentStep()
  {
          EditStatus()
  {
          Infos1()
  {
          StartDelay()
  {
          Infos2()
  {
} // end of class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA
.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums
       extends [System.Runtime]System.Object
{
  .class auto ansi sealed nested public GLOBAL_EnumSelectionType
         extends [System.Runtime]System.Enum
  {
    .field public specialname rtspecialname int32 value__
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_INITIAL_AS_CONFIG = int32(0x00000000)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_INITIAL_DEFAULT = int32(0x00000001)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_PARAMETRIZATION = int32(0x00000002)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_DESELECT = int32(0x00000003)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_INITIAL_FULL = int32(0x00000004)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_INITIAL_AS_CONFIG_VIA_RSS = int32(0x0000000A)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_INITIAL_DEFAULT_VIA_RSS = int32(0x0000000B)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_PARAMETRIZATION_TEMP = int32(0x0000000C)
    .field public static literal class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumSelectionType GLOBAL_LAST_PROGRAM_INFO = int32(0x0000000D)
  } // end of class GLOBAL_EnumSelectionType
} // end of class Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums
