.class public auto ansi beforefieldinit Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.AntiCreaseSettingSource
       extends class Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.Base.BaseApiSource`2<[Miele.Modules.LaundryCare.ApplianceCommunication.Contract]Miele.Modules.LaundryCare.ApplianceCommunication.Contract.ApplianceProperty.AntiCreaseSettingProperty,[Miele.Modules.LaundryCare.ApplianceCommunication.ApplianceData]Miele.LaundryCare.ApplianceData.DOP2.GLOBAL_SF_Value>
{
  .class auto ansi serializable sealed nested private beforefieldinit '<>c'
         extends [System.Runtime]System.Object
  {
    .field public static initonly class Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.AntiCreaseSettingSource/'<>c' '<>9'
    .field public static [System.Runtime]System.Func`2<[Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Instance`1<[Miele.Modules.LaundryCare.ApplianceCommunication.ApplianceData]Miele.LaundryCare.ApplianceData.DOP2.GLOBAL_SF_Value>,bool> '<>9__9_0'



  } // end of class '<>c'

  .method family hidebysig specialname virtual 
          instance uint32  get_ObjectId() cil managed
  {
    .maxstack  8
    IL_0000:  ldc.i4.s   105
    IL_0002:  ret
  } // end of method AntiCreaseSettingSource::get_ObjectId

  .method family hidebysig specialname virtual 
          instance uint32  get_Idx1() cil managed
  {
    .maxstack  8
    IL_0000:  ldc.i4     0x2f05
    IL_0005:  ret
  } // end of method AntiCreaseSettingSource::get_Idx1






  {
  {
  {
} // end of class Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.AntiCreaseSettingSource
.class public auto ansi beforefieldinit Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.Base.BaseApiSource`2<TReturn,([Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols]Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Dop2.Dop2Object) TContext>
       extends [System.Runtime]System.Object
       implements [Miele.Libraries.ApplianceCommunication.Implementation.Public]Miele.Libraries.ApplianceCommunication.Implementation.Public.ISource`1<[Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.LoadingBehavior.RetryableSnapshot`1<!TReturn>>,
                  [Miele.Libraries.ApplianceCommunication.Implementation.Public]Miele.Libraries.ApplianceCommunication.Implementation.Public.ISource
{
  .interfaceimpl type [Miele.Libraries.ApplianceCommunication.Implementation.Public]Miele.Libraries.ApplianceCommunication.Implementation.Public.ISource`1<[Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.LoadingBehavior.RetryableSnapshot`1<!TReturn>>
  .interfaceimpl type [Miele.Libraries.ApplianceCommunication.Implementation.Public]Miele.Libraries.ApplianceCommunication.Implementation.Public.ISource
  .field family initonly [Miele.Libraries.ApplianceCommunication.Client.Public]Miele.Libraries.ApplianceCommunication.Client.Public.Apis.IDop2Api _dop2Api
  .field private initonly [Miele.Libraries.ApplianceCommunication.Scheduler]Miele.Libraries.ApplianceCommunication.Scheduler.Schedulers.IBackgroundThreadScheduler _backgroundThreadScheduler
  .field family initonly [Microsoft.Extensions.Logging.Abstractions]Microsoft.Extensions.Logging.ILogger _logger
  .field private [Miele.Libraries.ApplianceCommunication.Repository.Public]Miele.Libraries.ApplianceCommunication.Repository.Public.MetaAppliance '<MetaAppliance>k__BackingField'
  .method family hidebysig newslot specialname virtual 
          instance uint32  get_Unit() cil managed
  {
    .maxstack  8
    IL_0000:  ldc.i4.2
    IL_0001:  ret
  } // end of method BaseApiSource`2::get_Unit



  .method family hidebysig newslot specialname virtual 
          instance uint32  get_Idx2() cil managed
  {
    .maxstack  8
    IL_0000:  ldc.i4.1
    IL_0001:  ret
  } // end of method BaseApiSource`2::get_Idx2













  {
  {
  {
  {
          MetaAppliance()
  {
  {
  {
} // end of class Miele.Modules.LaundryCare.ApplianceCommunication.Implementation.Sources.Base.BaseApiSource`2
