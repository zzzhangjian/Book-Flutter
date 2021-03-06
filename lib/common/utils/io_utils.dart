import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:thief_book_flutter/common/redux/progress_redux.dart';
import 'package:thief_book_flutter/common/server/articels_curd.dart';
import 'package:thief_book_flutter/common/server/books_curd.dart';
import 'package:thief_book_flutter/models/article.dart';
import 'package:thief_book_flutter/models/book.dart';
import 'package:thief_book_flutter/models/catalog.dart';

class IoUtils {
  ///拆解txt文本到章节
  static splitTxtByStream(
      String bookName, String sourcePath, store, path) async {
    if (sourcePath.indexOf(".zip") > 0) {
      File zipFile = new File(
          "/Users/joucks/Library/Developer/CoreSimulator/Devices/FDD6A480-A41B-4D73-BFA0-F20A30ECC134/data/Containers/Data/Application/7A1887AF-49C8-4186-AFD6-4E3B0A96F610/Documents/files/58741txt.zip");
      zipFile.open();
      return;
    }
    //bookName, "作者", "介绍", "字数", "imgUrl", "完结", sourcePath
    var book = new Book(
        name: bookName,
        author: "作者",
        info: "介绍",
        sourceAddress: "源地址url",
        sourceType: "源类型",
        catalogUrl: "在线目录地址",
        wordCount: "字数",
        imgUrl: "封面地址",
        status: "完结",
        importUrl: sourcePath);
    book = await BookApi.insertBook(book);
    File file = new File(sourcePath);
    //读取字节，并用Utf8解码
    // var fileSize = file.lengthSync();
    // var numBlockSize = (fileSize / 512).floor();
    // var lastBlockSize = fileSize % 512;
    // debugPrint("总长度:$fileSize,共:$numBlockSize块,剩余:$lastBlockSize块");
    // var one = numBlockSize * 512;
    // debugPrint("one:$one,two:${one + lastBlockSize}");
    var inputStream = file.openRead(); //0, 1024 * 128
    var lines = inputStream
        // 把内容用 utf-8 解码
        .transform(utf8.decoder)
        // 每次返回一行
        .transform(LineSplitter());
    RegExp exp = new RegExp(r"第\W+.{1,10}章");
    Article currAr = new Article(
        novelId: book.id,
        title: book.name,
        content: "",
        price: 0,
        currentIndex: 0,
        nextArticleId: 0,
        preArticleId: 0);
    await LocalCrud.deleteAll();
    //章节索引
    var inedx = 0;
    DateTime time = new DateTime.now();
    debugPrint("开始时间:${time.hour}:${time.minute}:${time.second}");
    var content = "";
    Directory bf = new Directory(path + "/" + book.id.toString());
    if (!bf.existsSync()) {
      bf.createSync();
    }
    var listCatalogJson = '{"data":[';
    await for (var line in lines) {
      Iterable<Match> matches = exp.allMatches(line);
      var lock = true;
      for (Match m in matches) {
        String match = m.group(0);
        debugPrint("章节-------$match");
        if (match.length < 14) {
          store.dispatch(new RefreshProgressDataAction("开始解析:" + match));
        }
        if (content.length > 0) {
          debugPrint("追加内容长度:${content.length}");
          currAr.content = content;

          File af = new File(path +
              "/" +
              book.id.toString() +
              "/article_" +
              currAr.id.toString() +
              ".json");
          af.createSync();
          af.writeAsStringSync(jsonEncode(currAr));
          // await LocalCrud.appendArticel(currAr);
          content = "";
        }
        //http://file.joucks.cn:3008/jianlai.txt
        inedx++;
        currAr = new Article(
            novelId: book.id,
            title: line,
            content: line,
            price: 0,
            currentIndex: inedx,
            nextArticleId: 0,
            preArticleId: 0);
        currAr.id = inedx;
        currAr.nextArticleId = currAr.id + 1;
        currAr.preArticleId = currAr.id - 1;
        // listCatalog
        //     .add(new Catalog(currAr.id, currAr.title, currAr.currentIndex));
        var cJson =
            new Catalog(currAr.id, currAr.title, null, currAr.currentIndex);

        listCatalogJson += jsonEncode(cJson) + ",";
        // currAr = await LocalCrud.insertArticel(obj);
        lock = false;
      }
      if (lock) {
        content += line;
        // await LocalCrud.appendArticel(currAr);
      }
    }
    File cf = new File(path + "/" + book.id.toString() + "/catalog.json");
    print("写入地址:${cf.path}");
    cf.createSync();
    listCatalogJson =
        listCatalogJson.substring(0, listCatalogJson.lastIndexOf(",")) + "]}";
    cf.writeAsStringSync(listCatalogJson);
    if (content != "") {
      debugPrint("最后一张的追加${content.length}");
      // currAr.content = content;
      // File lastAf = new File(path +
      //     "/" +
      //     book.id.toString() +
      //     "/article_" +
      //     currAr.id.toString() +
      //     ".json");
      // lastAf.createSync();
      // lastAf.writeAsStringSync(jsonEncode(currAr));
      // await LocalCrud.appendArticel(currAr);
    }
    // file.deleteSync();
    store.dispatch(new RefreshProgressDataAction(""));

    DateTime etime = new DateTime.now();
    debugPrint("结束时间:${etime.hour}:${etime.minute}:${etime.second}");
  }
}
