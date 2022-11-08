require 'logger'
require 'optparse'

# 適当なタイミングでバージョン更新を行う
# メジャーバージョン.マイナーバージョン.パッチバージョン
# メジャーバージョン: 互換性のない変更(APIの変更など)
# マイナーバージョン: 互換性のある新機能の追加(新しい機能の追加)
# パッチバージョン: 互換性のあるバグ修正
Version = '0.1.0'

class WHITESPACE
    # ログ出力用
    @@logger = Logger.new(STDOUT)

    ## リリース用レベル
    @@logger.level = Logger::WARN

    # インスタンス化時に実行される
    def initialize
        @buffer = nil

        # OptionParserのインスタンスを作成
        @opt = OptionParser.new

        # 各オプション(.parse!時実行)
        # デバッグ用
        @opt.on('-d', '--debug') {@@logger.level = Logger::DEBUG}

        # オプションを切り取る
        @opt.parse!(ARGV)

        # デバッグ状態の確認
        @@logger.debug('DEBUG MODE')

        # ファイルが指定されていた場合、ファイルを開く
        if ARGV.length > 0
            begin
                @buffer = ARGF.read
            rescue Errno::ENOENT => e
                @@logger.fatal(e.message)
                exit
            end
        else
            @@logger.fatal("ファイルが指定されていません")
            exit
        end
    end

end

WHITESPACE.new
