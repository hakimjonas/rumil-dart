import 'package:rumil/rumil.dart';
import 'package:rumil_parsers/rumil_parsers.dart';
import 'package:test/test.dart';

ProtoFile file_(Result<ParseError, ProtoFile> r) => switch (r) {
  Success<ParseError, ProtoFile>(:final value) => value,
  Partial<ParseError, ProtoFile>(:final value) => value,
  Failure() => throw StateError('Expected success, got ${r.errors}'),
};

void main() {
  group('Proto syntax', () {
    test('syntax statement', () {
      final f = file_(parseProto('syntax = "proto3";'));
      expect(f.syntax, 'proto3');
    });

    test('proto2 syntax', () {
      final f = file_(parseProto('syntax = "proto2";'));
      expect(f.syntax, 'proto2');
    });

    test('default syntax when omitted', () {
      final f = file_(parseProto(''));
      expect(f.syntax, 'proto3');
    });
  });

  group('Proto package', () {
    test('package statement', () {
      final f = file_(parseProto('syntax = "proto3";\npackage example.v1;\n'));
      final pkg = f.definitions.whereType<ProtoPackage>().first;
      expect(pkg.name, 'example.v1');
    });
  });

  group('Proto import', () {
    test('import statement', () {
      final f = file_(
        parseProto(
          'syntax = "proto3";\nimport "google/protobuf/timestamp.proto";\n',
        ),
      );
      final imp = f.definitions.whereType<ProtoImport>().first;
      expect(imp.path, 'google/protobuf/timestamp.proto');
      expect(imp.isPublic, false);
    });

    test('public import', () {
      final f = file_(
        parseProto('syntax = "proto3";\nimport public "other.proto";\n'),
      );
      final imp = f.definitions.whereType<ProtoImport>().first;
      expect(imp.isPublic, true);
    });
  });

  group('Proto message', () {
    test('simple message', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

message Person {
  string name = 1;
  int32 age = 2;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.name, 'Person');
      expect(msg.fields.length, 2);
      expect(msg.fields[0].name, 'name');
      expect(msg.fields[0].type, isA<ScalarType>());
      expect((msg.fields[0].type as ScalarType).scalar, ProtoScalar.string_);
      expect(msg.fields[0].number, 1);
      expect(msg.fields[1].name, 'age');
      expect(msg.fields[1].number, 2);
    });

    test('repeated field', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

message Container {
  repeated string items = 1;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.fields[0].rule, FieldRule.repeated);
      expect(msg.fields[0].type, isA<RepeatedType>());
    });

    test('message type reference', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

message Wrapper {
  Inner value = 1;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.fields[0].type, isA<NamedType>());
      expect((msg.fields[0].type as NamedType).name, 'Inner');
    });

    test('map field', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

message Config {
  map<string, int32> settings = 1;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.fields[0].type, isA<MapType>());
    });
  });

  group('Proto enum', () {
    test('enum definition', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

enum Status {
  UNKNOWN = 0;
  ACTIVE = 1;
  INACTIVE = 2;
}
'''),
      );
      final e = f.definitions.whereType<ProtoEnumDef>().first;
      expect(e.name, 'Status');
      expect(e.values.length, 3);
      expect(e.values[0].name, 'UNKNOWN');
      expect(e.values[0].number, 0);
      expect(e.values[2].name, 'INACTIVE');
    });
  });

  group('Proto service', () {
    test('service with RPC', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
}
'''),
      );
      final svc = f.definitions.whereType<ProtoServiceDef>().first;
      expect(svc.name, 'Greeter');
      expect(svc.methods.length, 1);
      expect(svc.methods[0].name, 'SayHello');
      expect(svc.methods[0].inputType, 'HelloRequest');
      expect(svc.methods[0].outputType, 'HelloReply');
      expect(svc.methods[0].inputStreaming, false);
    });

    test('streaming RPC', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

service UserService {
  rpc ListUsers (ListRequest) returns (stream User);
}
'''),
      );
      final svc = f.definitions.whereType<ProtoServiceDef>().first;
      expect(svc.methods[0].outputStreaming, true);
      expect(svc.methods[0].inputStreaming, false);
    });

    test('RPC with empty body', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

service Svc {
  rpc Do (Req) returns (Resp) {}
}
'''),
      );
      final svc = f.definitions.whereType<ProtoServiceDef>().first;
      expect(svc.methods.length, 1);
    });
  });

  group('Proto comments', () {
    test('line comments', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

// A person message
message Person {
  string name = 1; // full name
  int32 age = 2;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.fields.length, 2);
    });

    test('block comments', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

/* Multi-line
   comment */
message Thing {
  string id = 1;
}
'''),
      );
      final msg = f.definitions.whereType<ProtoMessageDef>().first;
      expect(msg.fields.length, 1);
    });
  });

  group('Proto complete file', () {
    test('full proto file', () {
      final f = file_(
        parseProto('''
syntax = "proto3";

package example;

import "common.proto";

message User {
  string id = 1;
  string name = 2;
  int32 age = 3;
  repeated string emails = 4;
}

enum Role {
  USER = 0;
  ADMIN = 1;
}

service UserService {
  rpc GetUser (UserRequest) returns (User);
  rpc ListUsers (ListRequest) returns (stream User);
}
'''),
      );
      expect(f.syntax, 'proto3');
      expect(f.definitions.whereType<ProtoPackage>().length, 1);
      expect(f.definitions.whereType<ProtoImport>().length, 1);
      expect(f.definitions.whereType<ProtoMessageDef>().length, 1);
      expect(f.definitions.whereType<ProtoEnumDef>().length, 1);
      expect(f.definitions.whereType<ProtoServiceDef>().length, 1);
    });
  });
}
