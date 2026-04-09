/// Generated JSON test data at various sizes.
library;

String jsonSmall() => '{"name":"Alice","age":30,"active":true}';

String jsonMedium() {
  final sb = StringBuffer('{"items":[');
  for (var i = 0; i < 500; i++) {
    if (i > 0) sb.write(',');
    sb.write(
      '{"id":$i,"name":"item_$i","value":${i * 1.5},'
      '"tags":["a","b","c"],"nested":{"x":$i,"y":${i + 1}}}',
    );
  }
  sb.write(']}');
  return sb.toString();
}

String jsonLarge() {
  final sb = StringBuffer('{"data":[');
  for (var i = 0; i < 5000; i++) {
    if (i > 0) sb.write(',');
    sb.write(
      '{"id":$i,"name":"record_$i","score":${i * 0.1},'
      '"active":${i % 2 == 0},'
      '"address":{"street":"${i}th Ave","city":"NYC","zip":"${10000 + i}"},'
      '"tags":["tag_${i % 10}","tag_${i % 20}","tag_${i % 30}"]}',
    );
  }
  sb.write(']}');
  return sb.toString();
}
