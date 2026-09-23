import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
class Localize extends RecursiveAstVisitor<void> {
 final inserts=<int,String>{}; final removes=<int,int>{};
 void wrap(Expression e, String fn) {
  if(e.toSource().startsWith('tr(')||e.toSource().startsWith('localizeValidator('))return;
  inserts[e.offset]='$fn(context, ${inserts[e.offset]??''}';
  inserts[e.end]='${inserts[e.end]??''})';
  for(AstNode? n=e.parent;n!=null;n=n.parent){
   if(n is InstanceCreationExpression && n.keyword?.lexeme=='const') removes[n.keyword!.offset]=n.keyword!.length;
   if(n is TypedLiteral && n.constKeyword!=null)removes[n.constKeyword!.offset]=n.constKeyword!.length;
   if(n is VariableDeclarationList && n.keyword?.lexeme=='const'){removes[n.keyword!.offset]=n.keyword!.length;inserts[n.keyword!.offset]='final';}
  }
 }
 @override void visitInstanceCreationExpression(InstanceCreationExpression n){
  final name=n.constructorName.type.toSource();
  if(['Text','SelectableText'].contains(name)&&n.constructorName.name==null&&n.argumentList.arguments.isNotEmpty){
   final e=n.argumentList.arguments.first;final source=e.toSource();
   final userContent=RegExp(r'\.(name|description|contact|email|reason|text)$').hasMatch(source)||source=="m['text'] as String";
   if(!userContent && !(e is SimpleStringLiteral && !RegExp('[А-Яа-яЁё]').hasMatch(e.value)))wrap(e,'tr');
  }
  super.visitInstanceCreationExpression(n);
 }
 @override void visitNamedExpression(NamedExpression n){
  final key=n.name.label.name;
  if(['tooltip','labelText','hintText','helperText','errorText','semanticLabel','semanticsLabel','barrierLabel','helpText','cancelText','confirmText'].contains(key)){
   if(n.expression is! NullLiteral)wrap(n.expression,'trNullable');
  }
  if(key=='validator')wrap(n.expression,'localizeValidator');
  super.visitNamedExpression(n);
 }
}
void main(){
 for(final file in Directory('lib').listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.dart')&&!f.path.contains('l10n'))){
  final s=file.readAsStringSync();if(!s.contains('package:flutter/material.dart'))continue;
  final v=Localize();parseString(content:s,throwIfDiagnostics:false).unit.accept(v);
  if(v.inserts.isEmpty)continue;
  var output='';for(var i=0;i<s.length;i++){output+=v.inserts[i]??'';if(v.removes.containsKey(i)){i+=v.removes[i]!-1;continue;}output+=s[i];}output+=v.inserts[s.length]??'';
  file.writeAsStringSync("import 'package:event_match/l10n/app_localizations.dart';\n$output");
  print(file.path);
 }
}
