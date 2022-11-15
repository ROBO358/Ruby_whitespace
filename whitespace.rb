require 'logger'
require 'optparse'
require 'strscan'

# 適当なタイミングでバージョン更新を行う
# メジャーバージョン.マイナーバージョン.パッチバージョン
# メジャーバージョン: 互換性のない変更(APIの変更など)
# マイナーバージョン: 互換性のある新機能の追加(新しい機能の追加)
# パッチバージョン: 互換性のあるバグ修正
Version = '0.2.0'

class WHITESPACE
    # ログ出力用
    @@logger = Logger.new(STDOUT)

    ## リリース用レベル
    @@logger.level = Logger::WARN

    # IMPシンボル表
    @@imp = {
        " " => :stack,
        "\t " => :arithmetic,
        "\t\t" => :heap,
        "\n" => :flow,
        "\t\n" => :io,
    }

    # CMDシンボル表
    # stack操作
    @@cmd_stack = {
        " " => :push,
        "\n " => :dup,
        "\t " => :copy,
        "\n\t" => :swap,
        "\n\n" => :discard,
        "\t\n" => :slide,
    }

    # 算術演算
    @@cmd_arithmetic = {
        "  " => :add,
        " \t" => :sub,
        " \n" => :mul,
        "\t " => :div,
        "\t\t" => :mod,
    }

    # ヒープアクセス
    @@cmd_heap = {
        " " => :store,
        "\t" => :retrieve,
    }

    # フロー制御
    @@cmd_flow = {
        "  " => :mark,
        " \t" => :call,
        " \n" => :jump,
        "\t " => :jump0,
        "\t\t" => :jumpn,
        "\t\n" => :ret,
        "\n\n" => :end,
    }

    # I/O制御
    @@cmd_io = {
        "  " => :output_label,
        " \t" => :output_num,
        "\t " => :read_chara,
        "\t\t" => :read_num,
    }

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

        # 字句解析実行
        tokens = _tokenize(@buffer)
        @@logger.debug("tokens: #{tokens}")
    end

    # 字句解析
    private def _tokenize(code)
        tokens = []
        scanner = StringScanner.new(code)

        # 末端まで読み込む
        while code.length > 0
            # impの取得
            imp, scanner = _imp_cutout(scanner)
            @@logger.debug("imp: #{imp}")

            # cmdの取得
            cmd, scanner = _cmd_cutout(imp, scanner)
            @@logger.debug("cmd: #{cmd}")

            # paramの取得
            param, scanner = _param_cutout(cmd, scanner)
            @@logger.debug("param: #{param}")

            # paramがある場合は、impとcmd,paramを結合
            if !param.nil?
                tokens << imp << cmd << param
            # paramがない場合は、impとcmdを結合
            else
                tokens << imp << cmd
            end
            @@logger.debug("tokenize: #{imp} #{cmd} #{param}")
            @@logger.debug("tokenize_array: #{tokens}")
        end

        return tokens
    end

    # IMP切り出し
    private def _imp_cutout(scanner)
        @@logger.debug("scanner: #{scanner.inspect}")

        # IMPの切り出し
        unless scanner.scan(/ |\n|\t[ \n\t]/)
            raise Exception, "IMPが不正です"
        end

        imp = nil
        # IMPをシンボルに変換
        if @@imp.has_key?(scanner.matched)
            imp = @@imp[scanner.matched]
        else
            raise Exception, "IMPが不正です"
        end

        return imp, scanner
    end

    # CMD切り出し
    private def _cmd_cutout(imp, scanner)
        @@logger.debug("imp: #{imp}, scanner: #{scanner.inspect}")
        cmd = nil
        cmd_symbol = nil
        err = false

        # IMPによって、切り出すCMDを変更
        case imp
        # stack操作
        when :stack
            unless scanner.scan(/ |\n |\n\t|\n\n/)
                err = true
            else
                cmd_symbol = @@cmd_stack
            end

        # 算術演算
        when :arithmetic
            unless scanner.scan(/  | \t| \n|\t |\t\t/)
                err = true
            else
                cmd_symbol = @@cmd_arithmetic
            end

        # ヒープアクセス
        when :heap
            unless scanner.scan(/ |\t/)
                err = true
            else
                cmd_symbol = @@cmd_heap
            end

        # フロー制御
        when :flow
            unless scanner.scan(/  | \t| \n|\t |\t\t|\t\n|\n\n/)
                err = true
            else
                cmd_symbol = @@cmd_flow
            end

        # IO
        when :io
            unless scanner.scan(/  | \t|\t |\t\t/)
                err = true
            else
                cmd_symbol = @@cmd_io
            end

        else
            err = true
        end

        raise Exception, "CMDが不正です" if err

        cmd = nil

        # CMDをシンボルに変換
        if cmd_symbol.has_key?(scanner.matched)
            cmd = cmd_symbol[scanner.matched]
        else
            raise Exception, "IMPが不正です"
        end

        return cmd, scanner
    end

    # PARAM切り出し
    private def _param_cutout(cmd, scanner)
        @@logger.debug("cmd: #{cmd}, scanner: #{scanner.inspect}")
        param = nil

        # PARAMがあるCMDの場合、PARAMを切り出す
        if cmd.match?(/push|copy|slide|mark|call|jump|jump0|jumpn/)
            unless scanner.scan(/[ \t]+\n/)
                raise Exception, "PARAMが不正です"
            end
        else
            return nil, scanner
        end

        # 取得したPARAMをローカル変数へ格納(今後の変換のため)
        param = scanner.matched

        return param, scanner
    end
end

# 実行
WHITESPACE.new
