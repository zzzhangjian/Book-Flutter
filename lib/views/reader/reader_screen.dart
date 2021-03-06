import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thief_book_flutter/common/config/config.dart';
import 'package:thief_book_flutter/common/server/books_curd.dart';
import 'package:thief_book_flutter/common/utils/request.dart';
import 'package:thief_book_flutter/common/utils/screen.dart';
import 'package:thief_book_flutter/common/utils/sp_uitls.dart';
import 'package:thief_book_flutter/common/utils/toast.dart';
import 'package:thief_book_flutter/main.dart';
import 'package:thief_book_flutter/models/article.dart';
import 'package:thief_book_flutter/models/chapter.dart';
import 'package:thief_book_flutter/views/reader/reader_source_core.dart';
import 'package:thief_book_flutter/widgets/progress_dialog.dart';
import 'dart:async';
import 'reader_utils.dart';
import 'reader_config.dart';
import 'reader_page_agent.dart';
import 'reader_menu.dart';
import 'reader_view.dart';

enum PageJumpType { stay, firstPage, lastPage }

class ReaderScene extends StatefulWidget {
  final int novelId;
  final String sourceType; //来源
  final String catalogUrl;
  bool isOlineRedaer; //在线阅读?
  ReaderScene(
      {this.novelId, this.sourceType, this.isOlineRedaer, this.catalogUrl});
  @override
  ReaderSceneState createState() => ReaderSceneState();
}

class ReaderSceneState extends State<ReaderScene> with RouteAware {
  double spFontSize = ReaderConfig.instance.fontSize;
  bool isVertical = true; //是否横屏
  int pageIndex = 0;
  bool isMenuVisiable = false;
  PageController pageController;
  bool isLoading = false;
  bool idLoadingOline = false;
  double topSafeHeight = 0;
  int chapterIndex = 0;
  Article preArticle;
  Article currentArticle;
  Article nextArticle;
  int bookId = 0;
  var basePath = "";
  String fisrtSourceLink = "";

  List<Chapter> chapters = [];
 
  @override
  void initState() {
    super.initState();
    if (this.widget.isOlineRedaer) {
      onlineSetup(this.widget.novelId);
    } else {
      setup(this.widget.novelId);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context));
  }

  @override
  void didPop() {
    SystemChrome.setEnabledSystemUIOverlays(
        [SystemUiOverlay.top, SystemUiOverlay.bottom]);
  }

  @override
  void dispose() {
    if (pageController != null) {
      print("释放阅读页pageController");
      pageController.dispose();
    }
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  //在线阅读初始方法
  void onlineSetup(novelId) async {
    var currentArticleId = 1;
    await SystemChrome.setEnabledSystemUIOverlays([]);
    SpUtils.setInt(Config.spCacheBookId, novelId);
    // 不延迟的话，安卓获取到的topSafeHeight是错的。
    await Future.delayed(const Duration(milliseconds: 300), () {});
    //setSystemUIOverlayStyle 用来设置状态栏顶部和底部样式，默认有 light 和 dark 模式，也可以按照需求自定义样式；
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    print("目录源链接：${this.widget.catalogUrl}");
    if (basePath == "") {
      basePath = await Config.getLocalFilePath(this.context);
    }
    var okPath = basePath + '/' + novelId.toString() + "/catalog.json";
    File f = new File(okPath);
    if (!f.existsSync()) {
      //不存在缓存目录则走在线抓取
      chapters = await RedaerRequest.getCotalogByOline(
          this.widget.catalogUrl, this.widget.sourceType);
    } else {
      var responseStr = await rootBundle.loadString(okPath);
      var jsonStr = json.decode(responseStr);
      List<dynamic> chaptersResponse = jsonStr["data"];
      chaptersResponse.forEach((data) {
        chapters.add(Chapter.fromJson(data));
      });
    }

    topSafeHeight = Screen.topSafeHeight;
    if (chapters.length < 3) {}
    var linkUrl = chapters[0].linkUrl;
    fisrtSourceLink = linkUrl;
    //获取已读到的章节
    var exArticleLink =
        await SpUtils.getValue(Config.spCacheArticleId + fisrtSourceLink);
    if (exArticleLink != null) {
      linkUrl = exArticleLink;
    }
    await resetContent(
        this.widget.novelId, currentArticleId, linkUrl, PageJumpType.stay);
  }

  //缓存阅读初始方法
  void setup(novelId) async {
    var currentArticleId = 0;
    await SystemChrome.setEnabledSystemUIOverlays([]);
    SpUtils.setInt(Config.spCacheBookId, novelId);
    // 不延迟的话，安卓获取到的topSafeHeight是错的。
    await Future.delayed(const Duration(milliseconds: 300), () {});
    //setSystemUIOverlayStyle 用来设置状态栏顶部和底部样式，默认有 light 和 dark 模式，也可以按照需求自定义样式；
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    topSafeHeight = Screen.topSafeHeight;
    // List<dynamic> chaptersResponse =
    // await ArticleProvider.getArticelAll(this.widget.novelId);
    if (basePath == "") {
      basePath = await Config.getLocalFilePath(this.context);
    }

    ///storage/emulated/0/Android/data/com.example.thief_book_flutter/files/2/catalog.json
    var responseStr = await rootBundle
        .loadString(basePath + '/' + novelId.toString() + "/catalog.json");
    var jsonStr = json.decode(responseStr);
    List<dynamic> chaptersResponse = jsonStr["data"];
    chaptersResponse.forEach((data) {
      chapters.add(Chapter.fromJson(data));
    });
    var idStr = this.widget.novelId.toString();
    //获取已读到的章节
    var exArticleId = await SpUtils.getInt(Config.spCacheArticleId + idStr);
    if (exArticleId != null) {
      currentArticleId = exArticleId;
      print("取出的缓存章节id:$currentArticleId");
    }
    await resetContent(
        this.widget.novelId, currentArticleId, null, PageJumpType.stay);
  }

  resetContent(
      int novelId, int articleId, String linkUrl, PageJumpType jumpType) async {
    var isExists = await Request.isExistsCacheByArticle(
        basePath, this.widget.novelId.toString(), articleId.toString());
    print("当前章节是否存在缓存:$isExists,id:$articleId");
    //是否在线阅读 this.widget.isOlineRedaer
    if (!isExists) {
      idLoadingOline = true;
      ProgressDialog.showLoadingDialog(context, "在线加载中..");
    }
    print("重置章节:---------------------------$jumpType");
    var fontSize = await ReaderConfig.instance.getFontSize();
    if (fontSize != null) {
      spFontSize = fontSize;
    }
    var spIsVertical = await ReaderConfig.instance.isVertical();
    print("默认横屏竖屏:$isVertical,历史竖屏:$spIsVertical");
    if (spIsVertical != null) {
      isVertical = spIsVertical;
    }
    currentArticle = await fetchArticle(articleId: articleId, linkUrl: linkUrl);
    if (currentArticle.preLink != null ||
        (currentArticle.preArticleId != null &&
            currentArticle.preArticleId > 0)) {
      preArticle = await fetchArticle(
        articleId: currentArticle.preArticleId,
        linkUrl: currentArticle.preLink,
      );
    } else {
      preArticle = null;
    }
    if (currentArticle.nextLink != null ||
        (currentArticle.nextArticleId != null &&
            currentArticle.nextArticleId > 0)) {
      nextArticle = await fetchArticle(
        articleId: currentArticle.nextArticleId,
        linkUrl: currentArticle.nextLink,
      );
    } else {
      nextArticle = null;
    }
    if (jumpType == PageJumpType.firstPage) {
      pageIndex = 0;
    } else if (jumpType == PageJumpType.lastPage) {
      pageIndex = currentArticle.pageCount - 1;
    }
    if (jumpType != PageJumpType.stay) {
      var toPage = (preArticle != null ? preArticle.pageCount : 0) + pageIndex;
      pageController.jumpToPage(toPage);
    }
    //初次进入
    if (jumpType == PageJumpType.stay) {
      //获取已读到的页数
      var exPageIndex;
      if (this.widget.isOlineRedaer) {
        exPageIndex =
            await SpUtils.getInt(Config.spCachePageIndex + fisrtSourceLink);
        print("在线已存在的页数:$exPageIndex");
        if (exPageIndex != null) {
          print("取出在线阅读缓存页数:$exPageIndex");
          pageIndex = exPageIndex;
        }
      } else {
        var idStr = this.widget.novelId.toString();
        exPageIndex = await SpUtils.getInt(Config.spCachePageIndex + idStr);
        print("缓存已存在的页数:$exPageIndex");
        if (exPageIndex != null) {
          print("取出缓存页数:$exPageIndex");
          pageIndex = exPageIndex;
        }
      }
      pageIndex = (preArticle != null ? preArticle.pageCount : 0) + pageIndex;
      pageController = PageController(keepPage: false, initialPage: pageIndex);
      pageController.addListener(onScroll);
    }
    setState(() {
      if (idLoadingOline) {
        idLoadingOline = false;
        Navigator.pop(context);
      }
    });
  }

  onScroll() {
    var sreenWidth = isVertical ? Screen.width : Screen.height;
    var page = pageController.offset / sreenWidth;
    var idStr = this.widget.novelId.toString();
    var nextArtilePage = currentArticle.pageCount +
        (preArticle != null ? preArticle.pageCount : 0);
    if (page >= nextArtilePage) {
      preArticle = currentArticle;
      currentArticle = nextArticle;
      nextArticle = null;
      pageIndex = 0;
      pageController.jumpToPage(preArticle.pageCount);
      fetchNextArticle(
          articleId: currentArticle.nextArticleId,
          linkUrl: currentArticle.nextLink);
      print('到达下个章节了,存入已读的章节:${currentArticle.id}');
      //缓存章节
      if (this.widget.isOlineRedaer) {
        SpUtils.setValue(Config.spCacheArticleId + fisrtSourceLink,
            currentArticle.currentLink);
      } else {
        SpUtils.setInt(Config.spCacheArticleId + idStr, currentArticle.id);
      }
      setState(() {});
    }
    if (preArticle != null && page <= preArticle.pageCount - 1) {
      nextArticle = currentArticle;
      currentArticle = preArticle;
      preArticle = null;
      pageIndex = currentArticle.pageCount - 1;
      pageController.jumpToPage(currentArticle.pageCount - 1);
      fetchPreviousArticle(
          articleId: currentArticle.preArticleId,
          linkUrl: currentArticle.preLink);
      print('到达上个章节了,存入已读的章节:${currentArticle.id}');
      if (this.widget.isOlineRedaer) {
        SpUtils.setValue(Config.spCacheArticleId + fisrtSourceLink,
            currentArticle.currentLink);
      } else {
        SpUtils.setInt(Config.spCacheArticleId + idStr, currentArticle.id);
      }
      setState(() {});
    }
  }

  fetchPreviousArticle({int articleId, String linkUrl}) async {
    if (preArticle != null || isLoading || articleId == 0) {
      return;
    }
    isLoading = true;
    if (articleId != null) {
      preArticle = await fetchArticle(articleId: articleId, linkUrl: linkUrl);
    } else {
      preArticle = null;
    }
    if (preArticle == null) {
      return;
    }
    pageController.jumpToPage(preArticle.pageCount + pageIndex);
    isLoading = false;
    setState(() {});
  }

  fetchNextArticle({int articleId, String linkUrl}) async {
    if (nextArticle != null || isLoading || articleId == 0) {
      return;
    }
    isLoading = true;
    nextArticle = await fetchArticle(articleId: articleId, linkUrl: linkUrl);
    isLoading = false;
    setState(() {});
  }

  Future<Article> fetchArticle({int articleId, String linkUrl}) async {
    var article = new Article();

    var isExists = await Request.isExistsCacheByArticle(
        basePath, this.widget.novelId.toString(), articleId.toString());
    print("当前章节是否存在缓存:$isExists,id:$articleId");
    //是否在线阅读 this.widget.isOlineRedaer
    if (!isExists) {
      article = await RedaerRequest.getArticleByOline(
          linkUrl: linkUrl, sourceType: this.widget.sourceType);
    } else {
      var jsonData = await Request.getArticleByPath(
          basePath, this.widget.novelId.toString(), articleId.toString());
      article = Article.fromJson(jsonData);
    }
    var contentHeight = Screen.height -
        topSafeHeight -
        ReaderUtils.topOffset -
        Screen.bottomSafeHeight -
        ReaderUtils.bottomOffset -
        20;
    var contentWidth = Screen.width - 15 - 10;
    var fontSize = await ReaderConfig.instance.getFontSize();
    article.pageOffsets = ReaderPageAgent.getPageOffsets(
        article.content, contentHeight, contentWidth, fontSize);

    return article;
  }

  onTap(Offset position) async {
    var sreenWidth = isVertical ? Screen.width : Screen.height;
    var positionNum = isVertical ? position.dx : position.dy;
    double xRate = positionNum / sreenWidth;
    if (xRate > 0.33 && xRate < 0.66) {
      SystemChrome.setEnabledSystemUIOverlays(
          [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      setState(() {
        isMenuVisiable = true;
      });
    } else if (xRate >= 0.66) {
      nextPage();
    } else {
      previousPage();
    }
  }

  onPageChanged(int index) {
    print("换页触发onPageChanged");
    var page = index - (preArticle != null ? preArticle.pageCount : 0);
    if (page < currentArticle.pageCount && page >= 0) {
      setState(() {
        pageIndex = page;
        if (pageIndex < currentArticle.pageCount) {
          //存入已读到的页数
          if (this.widget.isOlineRedaer) {
            SpUtils.setValue(Config.spCacheArticleId + fisrtSourceLink,
                currentArticle.currentLink);
            SpUtils.setInt(
                Config.spCachePageIndex + fisrtSourceLink, pageIndex);
          } else {
            print(
                "缓存换页，存入已读的页数:${pageIndex + 1},当前章共有页数:${currentArticle.pageCount}");
            var idStr = this.widget.novelId.toString();
            SpUtils.setInt(Config.spCacheArticleId + idStr, currentArticle.id);
            SpUtils.setInt(Config.spCachePageIndex + idStr, pageIndex);
          }
        }
      });
    }
  }

  previousPage() {
    if (pageIndex == 0 && currentArticle.preArticleId == 0) {
      Toast.show("已经是第一章了~");
      return;
    }
    pageController.previousPage(
        duration: Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  nextPage() {
    if (pageIndex >= currentArticle.pageCount - 1 &&
        currentArticle.nextArticleId == 0) {
      Toast.show("已经最后一页了~");
      return;
    }
    pageController.nextPage(
        duration: Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Widget buildPage(BuildContext context, int index) {
    var page = index - (preArticle != null ? preArticle.pageCount : 0);
    var article;
    if (page >= this.currentArticle.pageCount) {
      // 到达下一章了
      article = nextArticle;
      page = 0;
    } else if (page < 0) {
      // 到达上一章了
      article = preArticle;
      page = preArticle.pageCount - 1;
    } else {
      article = this.currentArticle;
    }

    return GestureDetector(
      onTapUp: (TapUpDetails details) {
        onTap(details.globalPosition);
      },
      child: ReaderView(
        article: article,
        page: page,
        topSafeHeight: topSafeHeight,
        fontSize: spFontSize,
      ),
    );
  }

  buildPageView() {
    if (currentArticle == null) {
      return Container();
    }
    int itemCount = (preArticle != null ? preArticle.pageCount : 0) +
        currentArticle.pageCount +
        (nextArticle != null ? nextArticle.pageCount : 0);
    return PageView.builder(
      scrollDirection: isVertical ? Axis.horizontal : Axis.vertical,
      physics: BouncingScrollPhysics(),
      controller: pageController,
      itemCount: itemCount,
      itemBuilder: buildPage,
      onPageChanged: onPageChanged,
    );
  }

  buildMenu() {
    if (!isMenuVisiable) {
      return Container();
    }
    return ReaderMenu(
        chapters: chapters,
        articleIndex: this.widget.isOlineRedaer
            ? (chapterIndex + 1)
            : currentArticle.currentIndex,
        onTap: hideMenu,
        onPreviousArticle: () {
          clearSpCachePageIndex();
          chapterIndex = chapterIndex--;
          print("点���上一章重置章节索引:$chapterIndex");
          chapterIndex = resetContent(
              this.widget.novelId,
              currentArticle.preArticleId,
              currentArticle.preLink,
              PageJumpType.firstPage);
        },
        onNextArticle: () {
          clearSpCachePageIndex();
          print("点击下一章重置章节索引:$chapterIndex");
          chapterIndex = chapterIndex++;
          resetContent(this.widget.novelId, currentArticle.nextArticleId,
              currentArticle.nextLink, PageJumpType.firstPage);
        },
        onToggleChapter: (Chapter chapter) async {
          clearSpCachePageIndex();
          chapterIndex = chapter.index;
          print("拖动进度条充值章节索引:$chapterIndex");
          var book = await BookApi.getBook(this.widget.novelId);
          print("拖动进度条获取到的book已缓存的索引:${book.isCacheIndex}");
          if (book.isCacheIndex < chapter.index) {
            //如果选中的索引越过缓存的索引则切换为在线阅读模式
            this.widget.isOlineRedaer = true;
          } else {
            this.widget.isOlineRedaer = false;
          }
          resetContent(this.widget.novelId, chapter.index + 1, chapter.linkUrl,
              PageJumpType.firstPage);
        },
        onEditSetting: () {
          // clearSpCachePageIndex();
          // Navigator.pushNamedAndRemoveUntil(context, '/page_c', ModalRoute.withName('/'));
          Navigator.of(context).pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ReaderScene(
                      novelId: this.widget.novelId,
                      isOlineRedaer: this.widget.isOlineRedaer,
                      catalogUrl: this.widget.catalogUrl,
                      sourceType: this.widget.sourceType)));
          // resetContent(
          //   this.widget.novelId,
          //   currentArticle.currentIndex,
          //   currentArticle.currentLink,
          //   PageJumpType.firstPage,
          // );
        });
  }

  //重置当前缓存的页数，重置为0 第一页
  clearSpCachePageIndex() {
    print("清空已缓存的页数！");
    var idStr = this.widget.novelId.toString();
    SpUtils.setInt(Config.spCachePageIndex + idStr, 0);
  }

  hideMenu() {
    SystemChrome.setEnabledSystemUIOverlays([]);
    setState(() {
      this.isMenuVisiable = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentArticle == null || chapters == null) {
      return Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: Image.asset(Config.readerBgImg,
                    fit: BoxFit.cover)),
            Center(
              child: Text("加载中..."),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: AnnotatedRegion(
        value: SystemUiOverlayStyle.dark,
        child: Stack(
          children: <Widget>[
            Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: Image.asset(Config.readerBgImg,
                    fit: BoxFit.cover)),
            buildPageView(),
            buildMenu(),
          ],
        ),
      ),
    );
  }
}
