# frozen_string_literal: true

require_relative '../../../schema/extract/grpc_stubs'

RSpec.describe Schema::Extract::GrpcStubs do
  let(:stub_file) { <<~JAVA }
    package systems.ajax.api.ecosystem.v3.mobilegwsvc.service.login_by_password;
    import defpackage.iz80;
    public final class LoginByPasswordServiceGrpcKt {
      public static final String SERVICE_NAME = "demo.login_by_password.LoginByPasswordService";
    }
  JAVA
  let(:obfuscated) { <<~JAVA }
    package defpackage;

    import demo.login_by_password.LoginByPasswordResponse;

    uunVarB.e = lda0.a;
    uunVarB.a = mda0.a(LoginByPasswordServiceGrpcKt.SERVICE_NAME, "execute");
    sy80 defaultInstance = sy80.getDefaultInstance();
    uunVarB.d = new luh0(LoginByPasswordResponse.getDefaultInstance());
    uunVarC.e = lda0.d;
    uunVarC.a = mda0.a("demo.stream.StreamService", "watch");
    ab12 defaultInstance = ab12.getDefaultInstance();
    uunVarC.d = new luh0(cd34.getDefaultInstance());
    uunVarD.e = lda0.a;
    uunVarD.a = mda0.a(UnknownGrpcKt.SERVICE_NAME, "lost");
    uunVarE.e = lda0.b;
    uunVarE.a = mda0.a("demo.stream.StreamService", "upload");
    uunVarF.e = lda0.c;
    uunVarF.a = mda0.a("demo.stream.StreamService", "follow");
  JAVA

  it 'maps the stub classes to the full name of their service' do
    expect(described_class.service_names(stub_file))
      .to eq('iz80' => 'demo.login_by_password.LoginByPasswordService',
             'LoginByPasswordServiceGrpcKt' => 'demo.login_by_password.LoginByPasswordService')
  end

  it 'reads the service, method, call type and message classes of each method it can name, by their full names' do
    expect(described_class.rpcs(obfuscated, described_class.service_names(stub_file)))
      .to eq([['demo.login_by_password.LoginByPasswordService', 'execute', :unary, 'defpackage.sy80',
               'demo.login_by_password.LoginByPasswordResponse'],
              ['demo.stream.StreamService', 'watch', :bidi, 'defpackage.ab12', 'defpackage.cd34'],
              ['demo.stream.StreamService', 'upload', :client_stream, nil, nil],
              ['demo.stream.StreamService', 'follow', :server_stream, nil, nil]])
  end
end
