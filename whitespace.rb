require 'logger'
require 'optparse'
require 'strscan'

# 適当なタイミングでバージョン更新を行う
# メジャーバージョン.マイナーバージョン.パッチバージョン
# メジャーバージョン: 互換性のない変更(APIの変更など)
# マイナーバージョン: 互換性のある新機能の追加(新しい機能の追加)
# パッチバージョン: 互換性のあるバグ修正
Version = '0.13.0'

class WHITESPACE
    # IMPシンボル表
    Imp = {
        " " => :stack,
        "\t " => :arithmetic,
        "\t\t" => :heap,
        "\n" => :flow,
        "\t\n" => :io,
    }

    # CMDシンボル表
    # stack操作
    Cmd_stack = {
        " " => :push,
        "\n " => :dup,
        "\t " => :copy,
        "\n\t" => :swap,
        "\n\n" => :discard,
        "\t\n" => :slide,
    }

    # 算術演算
    Cmd_arithmetic = {
        "  " => :add,
        " \t" => :sub,
        " \n" => :mul,
        "\t " => :div,
        "\t\t" => :mod,
    }

    # ヒープアクセス
    Cmd_heap = {
        " " => :store,
        "\t" => :retrieve,
    }

    # フロー制御
    Cmd_flow = {
        "  " => :mark,
        " \t" => :call,
        " \n" => :jump,
        "\t " => :jump0,
        "\t\t" => :jumpn,
        "\t\n" => :ret,
        "\n\n" => :end,
    }

    # I/O制御
    Cmd_io = {
        "  " => :output_label,
        " \t" => :output_num,
        "\t " => :read_chara,
        "\t\t" => :read_num,
    }

    # インスタンス化時に実行される
    def initialize
        buffer = nil

        # ログ出力用
        @logger = Logger.new(STDOUT)
        ## リリース用レベル
        @logger.level = Logger::WARN

        # OptionParserのインスタンスを作成
        opt = OptionParser.new

        # 各オプション(.parse!時実行)
        # デバッグ用
        opt.on('-d', '--debug') {@logger.level = Logger::DEBUG}

        # オプションを切り取る
        opt.parse!(ARGV)

        # デバッグ状態の確認
        @logger.debug('DEBUG MODE')

        # ファイルが指定されていた場合、ファイルを開く
        if ARGV.length > 0
            begin
                buffer = ARGF.read
            rescue Errno::ENOENT => e
                @logger.fatal(e.message)
                exit
            end
        else
            @logger.fatal("ファイルが指定されていません")
            exit
        end

        # 字句解析実行
        @tokens = _tokenize(buffer)
        @logger.debug("tokens: #{@tokens}")

        # 意味解析実行
        _evaluate()

    end

    # 字句解析
    private def _tokenize(code)
        tokens = []

        # 不要なコメントを削除
        code = code.delete("^[ \n\t]")

        scanner = StringScanner.new(code)

        # 末端まで読み込む
        while !scanner.eos?
            # impの取得
            imp, scanner = _imp_cutout(scanner)
            @logger.debug("imp: #{imp}")

            # cmdの取得
            cmd, scanner = _cmd_cutout(imp, scanner)
            @logger.debug("cmd: #{cmd}")

            # paramの取得
            param, scanner = _param_cutout(cmd, scanner)
            @logger.debug("param: #{param.inspect}")

            # paramがある場合は、impとcmd,paramを結合
            if !param.nil?
                tokens.push([imp, cmd, param])
            # paramがない場合は、impとcmdを結合
            else
                tokens.push([imp, cmd])
            end

            @logger.debug("tokenize: #{imp} #{cmd} #{param}")
            @logger.debug("tokenize_array: #{tokens}")
        end

        return tokens
    end

    # IMP切り出し
    private def _imp_cutout(scanner)
        @logger.debug("scanner: #{scanner.inspect}")

        # IMPの切り出し
        unless scanner.scan(/ |\n|\t[ \n\t]/)
            raise Exception, "IMPが不正です"
        end

        imp = nil
        # IMPをシンボルに変換
        if Imp.has_key?(scanner.matched)
            imp = Imp[scanner.matched]
        else
            raise Exception, "IMPが不正です"
        end

        return imp, scanner
    end

    # CMD切り出し
    private def _cmd_cutout(imp, scanner)
        @logger.debug("imp: #{imp}, scanner: #{scanner.inspect}")
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
                cmd_symbol = Cmd_stack
            end

        # 算術演算
        when :arithmetic
            unless scanner.scan(/  | \t| \n|\t |\t\t/)
                err = true
            else
                cmd_symbol = Cmd_arithmetic
            end

        # ヒープアクセス
        when :heap
            unless scanner.scan(/ |\t/)
                err = true
            else
                cmd_symbol = Cmd_heap
            end

        # フロー制御
        when :flow
            unless scanner.scan(/  | \t| \n|\t |\t\t|\t\n|\n\n/)
                err = true
            else
                cmd_symbol = Cmd_flow
            end

        # IO
        when :io
            unless scanner.scan(/  | \t|\t |\t\t/)
                err = true
            else
                cmd_symbol = Cmd_io
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
        @logger.debug("cmd: #{cmd}, scanner: #{scanner.inspect}")
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

    # 実行
    private def _evaluate()
        @stack = []
        @heap = {}
        @label = {}
        @subroutine = []
        @pc = 0

        loop do
            imp, cmd, param = @tokens[@pc]
            @logger.debug("imp: #{imp}, cmd: #{cmd}, param: #{param.inspect}")
            @logger.debug("pc: #{@pc}")

            @pc += 1

            # 存在しないコマンドを呼び出さないように
            # 正規表現にて存在しないものは呼び出しできないが、人間は愚かなので編集忘れてインジェクションされそうなので
            if Imp.values.include?(imp)
                @logger.debug("self.send: _#{imp.name}")
                # コマンドの実行
                self.send("_#{imp.name}", cmd, param)

            # 定義されていない場合
            else
                @logger.debug("imp: #{imp} is not defined")
                raise Exception, "存在しない操作です"
            end
        end
    end

    private def _stack(cmd, param)
        @logger.debug("STACK: cmd: #{cmd}, param: #{param.inspect}")

        case cmd
        when :push
            num = _to_i(param)
            @stack.push(num)
        when :dup
            @stack.push(@stack.last)
        when :copy
        when :swap
        when :discard
            @stack.pop
        when :slide
        else
            @logger.debug("cmd: #{cmd} is not defined")
            raise Exception, "存在しない操作です"
        end

        @logger.debug("STACK: after: #{@stack}")
    end

    private def _arithmetic(cmd, param)
        @logger.debug("ARITHMETIC: cmd: #{cmd}, param: #{param.inspect}")
        f_elm = @stack.pop
        s_elm = @stack.pop

        case cmd
        when :add
            @stack.push(f_elm + s_elm)
        when :sub
            @stack.push(f_elm - s_elm)
        when :mul
            @stack.push(f_elm * s_elm)
        when :div
            @stack.push(f_elm / s_elm)
        when :mod
            @stack.push(f_elm % s_elm)
        else
            @logger.debug("cmd: #{cmd} is not defined")
            raise Exception, "存在しない操作です"
        end

        @logger.debug("ARITHMETIC: after: #{@stack}")
    end

    private def _heap(cmd, param)
        @logger.debug("HEAP: cmd: #{cmd}, param: #{param.inspect}")

        case cmd
        when :store
            value = @stack.pop
            key = @stack.pop
            @heap[key] = value
        when :retrieve
        else
            @logger.debug("cmd: #{cmd} is not defined")
            raise Exception, "存在しない操作です"
        end
    end

    private def _flow(cmd, param)
        @logger.debug("FLOW: cmd: #{cmd}, param: #{param.inspect}")

        case cmd
        when :mark
            p = _to_i(param)
            @logger.debug("FLOW: mark: #{p}(#{@pc})")
            @label[p] = @pc
        when :call
        when :jump
            _jump(param)
        when :jump0
            if @stack.pop == 0
                _jump(param)
            else
                @logger.debug("FLOW: jump0: skip(to: #{_to_i(param)})")
            end
        when :jumpn
            if @stack.pop < 0
                _jump(param)
            else
                @logger.debug("FLOW: jumpn: skip(to: #{_to_i(param)})")
            end
        when :ret
        when :end
            @logger.debug("FLOW: end")
            exit
        else
            @logger.debug("cmd: #{cmd} is not defined")
            raise Exception, "存在しない操作です"
        end

        def _jump(param)
            p = _to_i(param)
            @logger.debug("FLOW: jump: #{p}")

            unless @label.has_key?(p)
                @tokens.each_with_index do |token, i|
                    if token[0] == :flow && token[1] == :mark && token[2] != nil
                        pp = _to_i(token[2])
                        @logger.debug("FLOW: mark: #{pp}(#{i})")
                        @label[pp] = i

                        if p == pp
                            break
                        end
                    end
                end
            end

            if @label.has_key?(p)
                @logger.debug("FLOW: jump: #{p}(#{@label[p]})")
                @pc = @label[p]
            else
                @logger.debug("FLOW: jump: #{p} is not defined")
                raise Exception, "存在しないラベルです"
            end
        end
    end

    private def _io(cmd, param)
        @logger.debug("IO: cmd: #{cmd}, param: #{param.inspect}")

        case cmd
        when :output_label
            @logger.debug("IO: output_label: #{@stack.last.to_s}")
            print @stack.pop.chr
        when :output_num
            @logger.debug("IO: output_num: #{@stack.last}")
            print @stack.pop.to_i
        when :read_chara
        when :read_num
        else
            @logger.debug("cmd: #{cmd} is not defined")
            raise Exception, "存在しない操作です"
        end
    end

    private def _to_i(param)

        # 正負判定
        num = '+' if param[0] == " "
        num = '-' if param[0] == "\t"

        # 数値判定
        param = param[1..-1]
        param = param.gsub(" ", '0')
        param = param.gsub("\t", "1")
        num += param[0..-2]

        # 2進数を10進数に変換
        num = num.to_i(2)
        @logger.debug("num: #{num}")

        return num
    end
end

# 実行
WHITESPACE.new
