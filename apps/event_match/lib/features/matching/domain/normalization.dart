/// Canonical identifiers at the matching boundary; display labels stay Russian.
String normalize(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');

const synonyms = <String, Map<String, List<String>>>{
  'city': {
    'almaty': ['Алматы', 'Almaty', 'алма-ата'],
    'astana': ['Астана', 'Astana', 'нур-султан'],
    'abroad': ['Зарубежье', 'abroad'],
  },
  'format': {
    'wedding': ['свадьба', 'үйлену тойы', 'wedding'],
    'toi': ['той', 'той-думан', 'toi'],
    'corporate': ['корпоратив', 'corporate'],
    'conference': ['конференция', 'conference'],
    'anniversary': ['юбилей', 'anniversary'],
    'birthday': ['день рождения', 'birthday'],
  },
  'language': {
    'ru': ['русский', 'рус', 'орыс тілі', 'ru'],
    'kk': ['казахский', 'қазақ тілі', 'каз', 'kk'],
    'en': ['английский', 'english', 'en'],
  },
  'category': {
    'host': ['Ведущий', 'MC', 'тамада'],
    'photographer': ['Фотограф', 'photographer'],
    'venue': ['Банкетный зал', 'зал', 'venue'],
    'florist': ['Флорист', 'florist'],
    'decorator': ['Декоратор', 'decorator'],
    'gifts': ['Подарки и сувениры', 'gifts'],
    'ceremony': ['Ведущий церемонии', 'ceremony'],
    'booth': ['Фото и видеобудки', 'booth'],
    'hotel': ['Отель', 'hotel'],
    'musician': ['Инструменталист', 'musician'],
    'band': ['Лайв-бэнд', 'band'],
  },
};

String canonical(String field, String value) {
  final normalized = normalize(value);
  for (final e in synonyms[field]!.entries) {
    if (e.key == normalized || e.value.any((v) => normalize(v) == normalized)) {
      return e.key;
    }
  }
  return normalized;
}

String displayValue(String field, String value) =>
    synonyms[field]?[canonical(field, value)]?.first ?? value.trim();

const formatKeywords = <String, List<String>>{
  'wedding': ['свад', 'никах', 'беташар', 'молодож'],
  'toi': ['той', 'беташар', 'казах'],
  'corporate': ['корпоратив', 'тимбилдинг', 'команд', 'компан'],
  'conference': ['конференц', 'делов', 'форум'],
  'anniversary': ['юбиле', 'семейн'],
  'birthday': ['день рожден', 'дня рожден', 'именин'],
};

const genericPhrases = [
  'отличный выбор',
  'идеально подойдет',
  'профессионал своего дела',
  'незабываемый праздник',
  'качественно и в срок',
];
