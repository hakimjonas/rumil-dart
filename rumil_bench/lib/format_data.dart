/// Generated test data for format parser benchmarks.
///
/// Each format has a small and large variant to measure both latency and
/// throughput characteristics.
library;

String csvSmall() {
  final sb = StringBuffer('name,age,city,email,active\r\n');
  for (var i = 0; i < 100; i++) {
    sb.write(
      '"User $i",$i,"City ${i % 20}","user$i@example.com",${i.isEven}\r\n',
    );
  }
  return sb.toString();
}

String csvLarge() {
  final sb = StringBuffer('id,name,score,department,"description"\r\n');
  for (var i = 0; i < 1000; i++) {
    sb.write('$i,"Employee $i",${i * 1.5},"Dept ${i % 10}",');
    sb.write(
      '"A longer description with ""quotes"" and, commas for row $i"\r\n',
    );
  }
  return sb.toString();
}

String tomlSmall() => '''
[server]
host = "localhost"
port = 8080
workers = 4
debug = false

[database]
url = "postgres://localhost/mydb"
pool_size = 10
timeout = 30

[logging]
level = "info"
file = "/var/log/app.log"
rotate = true

[features]
enable_cache = true
cache_ttl = 3600
max_connections = 100
rate_limit = 1000

[auth]
secret = "my-secret-key"
token_expiry = 86400
refresh_enabled = true
''';

String tomlLarge() {
  final sb = StringBuffer();
  sb.writeln('title = "Application Configuration"');
  sb.writeln('version = "2.1.0"');
  sb.writeln('');
  for (var i = 0; i < 50; i++) {
    sb.writeln('[services.service_$i]');
    sb.writeln('name = "service-$i"');
    sb.writeln('port = ${8000 + i}');
    sb.writeln('enabled = ${i.isEven}');
    sb.writeln('timeout = ${i * 100}');
    sb.writeln('tags = ["tag_${i % 5}", "tag_${i % 10}"]');
    sb.writeln('');
  }
  return sb.toString();
}

String xmlSmall() {
  final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  sb.write('<catalog>\n');
  for (var i = 0; i < 20; i++) {
    sb.write(
      '  <book id="bk$i" genre="${["fiction", "tech", "science"][i % 3]}">\n',
    );
    sb.write('    <title>Book Title $i</title>\n');
    sb.write('    <author>Author ${i % 10}</author>\n');
    sb.write('    <price>${9.99 + i}</price>\n');
    sb.write('    <year>${2000 + i}</year>\n');
    sb.write('  </book>\n');
  }
  sb.write('</catalog>');
  return sb.toString();
}

String xmlLarge() {
  final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  sb.write('<database>\n');
  for (var i = 0; i < 200; i++) {
    sb.write(
      '  <record id="$i" type="${["user", "order", "product"][i % 3]}">\n',
    );
    sb.write('    <name>Record $i</name>\n');
    sb.write('    <value>${i * 1.5}</value>\n');
    sb.write('    <metadata>\n');
    sb.write('      <created>2024-01-${(i % 28) + 1}</created>\n');
    sb.write('      <tags>tag_${i % 5},tag_${i % 10}</tags>\n');
    sb.write('    </metadata>\n');
    sb.write('  </record>\n');
  }
  sb.write('</database>');
  return sb.toString();
}

String yamlSmall() => '''
server:
  host: localhost
  port: 8080
  workers: 4
  debug: false
database:
  url: "postgres://localhost/mydb"
  pool_size: 10
  timeout: 30
logging:
  level: info
  file: /var/log/app.log
  rotate: true
features:
  - name: cache
    enabled: true
    ttl: 3600
  - name: rate_limit
    enabled: false
    max: 1000
''';

String yamlLarge() {
  final sb = StringBuffer('services:\n');
  for (var i = 0; i < 100; i++) {
    sb.writeln('  service_$i:');
    sb.writeln('    name: "service-$i"');
    sb.writeln('    port: ${8000 + i}');
    sb.writeln('    enabled: ${i.isEven}');
    sb.writeln('    tags: [tag_${i % 5}, tag_${i % 10}]');
    sb.writeln('    config:');
    sb.writeln('      timeout: ${i * 100}');
    sb.writeln('      retries: ${i % 5}');
    sb.writeln('      endpoint: "https://svc-$i.example.com/api/v1"');
  }
  return sb.toString();
}

String hclSmall() => r'''
variable "region" {
  type    = string
  default = "us-east-1"
}

resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  tags = {
    Name        = "web-server"
    Environment = var.region
  }
}

output "instance_id" {
  value = aws_instance.web.id
}
''';

String hclLarge() {
  final sb = StringBuffer();
  sb.writeln('variable "env" {');
  sb.writeln('  type    = string');
  sb.writeln('  default = "production"');
  sb.writeln('}');
  sb.writeln();
  for (var i = 0; i < 50; i++) {
    sb.writeln('resource "aws_instance" "server_$i" {');
    sb.writeln(
      '  ami           = "ami-${i.toRadixString(16).padLeft(8, '0')}"',
    );
    sb.writeln('  instance_type = "t3.${["micro", "small", "medium"][i % 3]}"');
    sb.writeln('  count         = ${i % 5 + 1}');
    sb.writeln();
    sb.writeln('  tags = {');
    sb.writeln('    Name = "server-$i-\${var.env}"');
    sb.writeln('    Role = "${["web", "api", "worker", "db"][i % 4]}"');
    sb.writeln('  }');
    sb.writeln();
    sb.writeln('  lifecycle {');
    sb.writeln('    create_before_destroy = ${i.isEven ? "true" : "false"}');
    sb.writeln('  }');
    sb.writeln('}');
    sb.writeln();
  }
  return sb.toString();
}

String protoSmall() => '''
syntax = "proto3";

package example.v1;

message User {
  string name = 1;
  int32 age = 2;
  string email = 3;
  bool active = 4;
  repeated string tags = 5;
}

enum Status {
  STATUS_UNSPECIFIED = 0;
  STATUS_ACTIVE = 1;
  STATUS_INACTIVE = 2;
}

service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc ListUsers(ListUsersRequest) returns (stream User);
}

message GetUserRequest {
  string id = 1;
}

message ListUsersRequest {
  int32 page_size = 1;
  string page_token = 2;
}
''';

String protoLarge() {
  final sb = StringBuffer();
  sb.writeln('syntax = "proto3";');
  sb.writeln('package benchmark.v1;');
  sb.writeln();
  for (var i = 0; i < 50; i++) {
    sb.writeln('message Record$i {');
    for (var f = 0; f < 10; f++) {
      final type = ['string', 'int32', 'int64', 'bool', 'double'][f % 5];
      sb.writeln('  $type field_$f = ${f + 1};');
    }
    sb.writeln('  repeated string tags = 11;');
    sb.writeln('  map<string, string> metadata = 12;');
    sb.writeln('}');
    sb.writeln();
  }
  sb.writeln('service BenchmarkService {');
  for (var i = 0; i < 20; i++) {
    sb.writeln('  rpc Method$i(Record$i) returns (Record${i + 1});');
  }
  sb.writeln('}');
  return sb.toString();
}
