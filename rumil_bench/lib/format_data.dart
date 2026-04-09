/// Generated test data for format parser benchmarks.
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
