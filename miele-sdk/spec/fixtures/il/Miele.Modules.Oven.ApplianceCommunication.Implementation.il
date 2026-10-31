.class public auto ansi beforefieldinit Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource
       extends class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.Base.Dop2Source`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity>
{
  .class abstract auto ansi sealed nested private beforefieldinit '<>O'
         extends [System.Runtime]System.Object
  {
    .field public static [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_DeviceContext>,[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_EnumProgramTypes> '<0>__ExtractProgramType'
    .field public static [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,int32> '<1>__GetProgramStepsCount'
  } // end of class '<>O'

  .class auto ansi serializable sealed nested private beforefieldinit '<>c'
         extends [System.Runtime]System.Object
  {
    .field public static initonly class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c' '<>9'
    .field public static [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Instance`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramStepInfoCA>,[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramStepInfoCA> '<>9__13_0'



  } // end of class '<>c'

  .class auto ansi sealed nested private beforefieldinit '<>c__DisplayClass10_0'
         extends [System.Runtime]System.Object
  {
    .field public class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource '<>4__this'
    .field public [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance metaAppliance


  } // end of class '<>c__DisplayClass10_0'

  .class auto ansi sealed nested private beforefieldinit '<>c__DisplayClass11_0'
         extends [System.Runtime]System.Object
  {
    .field public class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource '<>4__this'
    .field public [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance metaAppliance


  } // end of class '<>c__DisplayClass11_0'

  .class auto ansi sealed nested private beforefieldinit '<>c__DisplayClass11_1'
         extends [System.Runtime]System.Object
  {
    .class auto ansi sealed nested private beforefieldinit '<<ObserveProgramSteps>b__1>d'
           extends [System.Runtime]System.ValueType
           implements [System.Runtime]System.Runtime.CompilerServices.IAsyncStateMachine
    {
      .interfaceimpl type [System.Runtime]System.Runtime.CompilerServices.IAsyncStateMachine
      .field public int32 '<>1__state'
      .field public [System.Runtime]System.Runtime.CompilerServices.AsyncTaskMethodBuilder`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity> '<>t__builder'
      .field public class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_1' '<>4__this'
      .field private [System.Runtime]System.Runtime.CompilerServices.TaskAwaiter`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity> '<>u__1'


    } // end of class '<<ObserveProgramSteps>b__1>d'

    .field public [Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA> message
    .field public class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0' 'CS$<>8__locals1'


  } // end of class '<>c__DisplayClass11_1'

  .class auto ansi sealed nested private beforefieldinit '<>c__DisplayClass15_0'
         extends [System.Runtime]System.Object
  {
    .field public uint16 operationMode


  } // end of class '<>c__DisplayClass15_0'

  .class auto ansi sealed nested private beforefieldinit '<GetProgramStepsInfoAsync>d__13'
         extends [System.Runtime]System.ValueType
         implements [System.Runtime]System.Runtime.CompilerServices.IAsyncStateMachine
  {
    .interfaceimpl type [System.Runtime]System.Runtime.CompilerServices.IAsyncStateMachine
    .field public int32 '<>1__state'
    .field public [System.Runtime]System.Runtime.CompilerServices.AsyncTaskMethodBuilder`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity> '<>t__builder'
    .field public class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource '<>4__this'
    .field public [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance metaAppliance
    .field public int32 count
    .field private [System.Collections]System.Collections.Generic.List`1<[Miele.Modules.Oven.ApplianceCommunication.Contract]Miele.Modules.Oven.ApplianceCommunication.Contract.ModelValues.IProgramStep> '<programSteps>5__2'
    .field private uint32 '<i>5__3'
    .field private [System.Runtime]System.Runtime.CompilerServices.TaskAwaiter`1<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramStepInfoCA>> '<>u__1'


  } // end of class '<GetProgramStepsInfoAsync>d__13'

  .field public static literal int32 ProgramInfoUnit = int32(0x00000002)
  .field public static literal int32 ProgramInfoObjectId = int32(0x000000D5)
  .field public static literal int32 ProgramStepInfoUnit = int32(0x00000002)
  .field public static literal int32 ProgramStepInfoObjectId = int32(0x000000D6)
  .field private initonly [Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api _dop2Api
  .field private initonly class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.Helper.IDop2ReadHelper _dop2ReadHelper
  .field private initonly [Miele.Libraries.Localization]Miele.Libraries.Localization.Services.ILocalizationService _localizationService
  .field private initonly [System.Runtime]System.Collections.Generic.IEnumerable`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.Enums/GLOBAL_OP_EnumProgramStepTypeCA> _unsupportedStepTypes



  .method private hidebysig instance [System.Runtime]System.IObservable`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity> 
          ObserveProgramSteps([Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance metaAppliance) cil managed
  {
    .maxstack  6
    .locals init (class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0' V_0)
    IL_0000:  newobj     instance void Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0'::.ctor()
    IL_0005:  stloc.0
    IL_0006:  ldloc.0
    IL_0007:  ldarg.0
    IL_0008:  stfld      class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0'::'<>4__this'
    IL_000d:  ldloc.0
    IL_000e:  ldarg.1
    IL_000f:  stfld      [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0'::metaAppliance
    IL_0014:  ldarg.0
    IL_0015:  ldfld      [Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource::_dop2Api
    IL_001a:  ldloc.0
    IL_001b:  ldfld      [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0'::metaAppliance
    IL_0020:  callvirt   instance string [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance::get_FabricationNumber()
    IL_0025:  ldc.i4.2
    IL_0026:  ldc.i4     0xd5
    IL_002b:  ldc.i4.0
    IL_002c:  ldc.i4.1
    IL_002d:  callvirt   instance [System.Runtime]System.IObservable`1<!!0> [Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api::ObserveDop2Field<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>>(string,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     uint32,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     uint32,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     uint32,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     uint32)
    IL_0032:  ldsfld     [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,int32> Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>O'::'<1>__GetProgramStepsCount'
    IL_0037:  dup
    IL_0038:  brtrue.s   IL_004d

    IL_003a:  pop
    IL_003b:  ldnull
    IL_003c:  ldftn      int32 Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource::GetProgramStepsCount([Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>)
    IL_0042:  newobj     instance void [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,int32>::.ctor(object,
                                                                                                                                                                                                                                                                                                                                                                                                native int)
    IL_0047:  dup
    IL_0048:  stsfld     [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,int32> Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>O'::'<1>__GetProgramStepsCount'
    IL_004d:  call       [System.Runtime]System.IObservable`1<!!0> [System.Reactive]System.Reactive.Linq.Observable::DistinctUntilChanged<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,int32>([System.Runtime]System.IObservable`1<!!0>,
                                                                                                                                                                                                                                                                                                                                                                                                                                                              [System.Runtime]System.Func`2<!!0,!!1>)
    IL_0052:  ldloc.0
    IL_0053:  ldftn      instance [System.Runtime]System.IObservable`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity> Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource/'<>c__DisplayClass11_0'::'<ObserveProgramSteps>b__0'([Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>)
    IL_0059:  newobj     instance void [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,[System.Runtime]System.IObservable`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity>>::.ctor(object,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           native int)
    IL_005e:  call       [System.Runtime]System.IObservable`1<!!1> [System.Reactive]System.Reactive.Linq.Observable::Select<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Message`1<[Miele.Modules.Oven.ApplianceCommunication.Protocols]Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.GLOBAL_OP_ProgramInfoCA>,[System.Runtime]System.IObservable`1<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity>>([System.Runtime]System.IObservable`1<!!0>,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           [System.Runtime]System.Func`2<!!0,!!1>)
    IL_0063:  call       [System.Runtime]System.IObservable`1<!!0> [System.Reactive]System.Reactive.Linq.Observable::Switch<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity>([System.Runtime]System.IObservable`1<[System.Runtime]System.IObservable`1<!!0>>)
    IL_0068:  call       [System.Runtime]System.IObservable`1<!!0> [System.Reactive]System.Reactive.Linq.Observable::DistinctUntilChanged<class Miele.Modules.Oven.ApplianceCommunication.Implementation.Entities.ProgramStepsEntity>([System.Runtime]System.IObservable`1<!!0>)
    IL_006d:  ret
  } // end of method ProgramStepsSource::ObserveProgramSteps







} // end of class Miele.Modules.Oven.ApplianceCommunication.Implementation.Sources.DOP2.ProgramStepsSource
