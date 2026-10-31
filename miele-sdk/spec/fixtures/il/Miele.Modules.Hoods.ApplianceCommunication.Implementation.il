.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.AmbientLightingStateDop2Source
       extends class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.Dop2SourceBase`2<[Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Dop2.GLOBAL_PS_Context,class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Entity.AmbientLightingEntity>
{
  .method public hidebysig specialname rtspecialname 
          instance void  .ctor([Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api dop2Api,
                               class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Utils.IRetryHelper retryHelper,
                               [Miele.Libraries.Logging]Miele.Libraries.Logging.ILogService logService) cil managed
  {
    .maxstack  8
    IL_0000:  ldarg.0
    IL_0001:  ldc.i4     0x626
    IL_0006:  ldc.i4.2
    IL_0007:  newobj     instance void Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.Dop2RequestParameters::.ctor(uint32,
                                                                                                                                                  uint32)
    IL_000c:  ldarg.1
    IL_000d:  ldarg.2
    IL_000e:  ldarg.3
    IL_000f:  call       instance void class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.Dop2SourceBase`2<[Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.Dop2.GLOBAL_PS_Context,class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Entity.AmbientLightingEntity>::.ctor(class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.Dop2RequestParameters,
                                                                                                                                                                                                                                                                                                                                                                                           [Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api,
                                                                                                                                                                                                                                                                                                                                                                                           class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Utils.IRetryHelper,
                                                                                                                                                                                                                                                                                                                                                                                           [Miele.Libraries.Logging]Miele.Libraries.Logging.ILogService)
    IL_0014:  ret
  } // end of method AmbientLightingStateDop2Source::.ctor


} // end of class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Sources.Dop2Sources.AmbientLightingStateDop2Source

.class public auto ansi beforefieldinit Miele.Modules.Hoods.ApplianceCommunication.Implementation.Actions.DopActions.SetFanPowerLevelBaseAction
       extends Miele.Modules.Hoods.ApplianceCommunication.Implementation.Actions.DopActions.DopBaseAction
       implements [Miele.Modules.Hoods.ApplianceCommunication.Contract]Miele.Modules.Hoods.ApplianceCommunication.Contract.Actions.ISetFanPowerLevelAction,
                  [Miele.Modules.Hoods.ApplianceCommunication.Contract]Miele.Modules.Hoods.ApplianceCommunication.Contract.Actions.IConsciousAction,
                  [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.IAction,
                  [System.ObjectModel]System.ComponentModel.INotifyPropertyChanged
{
  .class auto ansi sealed nested private beforefieldinit '<SelectPowerLevelAsync>d__1'
         extends [System.Runtime]System.ValueType
         implements [System.Runtime]System.Runtime.CompilerServices.IAsyncStateMachine
  {
    .field public int32 '<>1__state'
    .field public [System.Runtime]System.Runtime.CompilerServices.AsyncTaskMethodBuilder`1<bool> '<>t__builder'
    .field public class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Actions.DopActions.SetFanPowerLevelBaseAction '<>4__this'
    .field public bool canSetFanLevel
    .field public [Miele.Modules.Hoods.ApplianceCommunication.Contract]Miele.Modules.Hoods.ApplianceCommunication.Contract.Enums.FanPowerLevel powerLevel
    .field private [System.Runtime]System.Runtime.CompilerServices.TaskAwaiter`1<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Response`1<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop1.Dop1Object>> '<>u__1'


  } // end of class '<SelectPowerLevelAsync>d__1'



  .method private hidebysig static [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung 
          CreateWriteObject([Miele.Modules.Hoods.ApplianceCommunication.Contract]Miele.Modules.Hoods.ApplianceCommunication.Contract.Enums.FanPowerLevel powerLevel) cil managed
  {
    .maxstack  8
    IL_0000:  ldc.i4.4
    IL_0001:  newarr     [System.Runtime]System.Byte
    IL_0006:  ldc.i4.0
    IL_0007:  ldc.i4.4
    IL_0008:  newobj     instance void [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung::.ctor(uint8[],
                                                                                                                                                                                                 int32,
                                                                                                                                                                                                 int32)
    IL_000d:  dup
    IL_000e:  callvirt   instance [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung::get_ServiceDataExt_LueftersteuerungInstance()
    IL_0013:  ldc.i4     0xff
    IL_0018:  callvirt   instance void [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection::set_Luefterauswahl(uint16)
    IL_001d:  dup
    IL_001e:  callvirt   instance [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung::get_ServiceDataExt_LueftersteuerungInstance()
    IL_0023:  ldarg.0
    IL_0024:  conv.u2
    IL_0025:  callvirt   instance void [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection::set_Luefterstufe(uint16)
    IL_002a:  dup
    IL_002b:  callvirt   instance [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung::get_ServiceDataExt_LueftersteuerungInstance()
    IL_0030:  ldc.i4.0
    IL_0031:  callvirt   instance void [Miele.Modules.Hoods.ApplianceCommunication.ApplianceData]Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection::set_Luefterleistung(uint16)
    IL_0036:  ret
  } // end of method SetFanPowerLevelBaseAction::CreateWriteObject

} // end of class Miele.Modules.Hoods.ApplianceCommunication.Implementation.Actions.DopActions.SetFanPowerLevelBaseAction
