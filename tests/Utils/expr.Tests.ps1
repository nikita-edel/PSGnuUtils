BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

# Expected results and exit codes come from GNU coreutils expr.
Describe 'expr' {
    It 'evaluates <Expression> to "<Output>" with exit code <ExitCode>' -ForEach @(
        @{ Expression = @('1', '+', '2'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('10', '/', '3'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('10', '%', '3'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('-7', '/', '2'); Output = '-3'; ExitCode = 0 }
        @{ Expression = @('-7', '%', '2'); Output = '-1'; ExitCode = 0 }
        @{ Expression = @('5', '*', '3'); Output = '15'; ExitCode = 0 }
        @{ Expression = @('1', '-', '1'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('99999999999999999999', '+', '1'); Output = '100000000000000000000'; ExitCode = 0 }
        @{ Expression = @('(', '1', '+', '2', ')', '*', '3'); Output = '9'; ExitCode = 0 }
        @{ Expression = @('a', '<', 'b'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('10', '<', '9'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('12', '<', '9'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('abc', '<', 'abd'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('a', '<=', 'a'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('b', '>', 'a'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('2', '>=', '3'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('2', '!=', '3'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('5', '=', '05'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('a', '==', 'A'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('', '=', ''); Output = '1'; ExitCode = 0 }
        @{ Expression = @('0', '|', '5'); Output = '5'; ExitCode = 0 }
        @{ Expression = @('', '|', '0'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('1', '|', '1', '/', '0'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('3', '&', '4'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('3', '&', '0'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('0', '&', '1', '/', '0'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('abc', ':', 'a\(.\)'); Output = 'b'; ExitCode = 0 }
        @{ Expression = @('abc', ':', 'a\(b\)\(c\)'); Output = 'b'; ExitCode = 0 }
        @{ Expression = @('abc', ':', 'b'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('abc', ':', '.*'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('abc', ':', '^a'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('abc', ':', '\(x\)*'); Output = ''; ExitCode = 1 }
        @{ Expression = @('match', 'abc', 'a.'); Output = '2'; ExitCode = 0 }
        @{ Expression = @('length', 'a b'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('substr', 'hello', '2', '3'); Output = 'ell'; ExitCode = 0 }
        @{ Expression = @('substr', 'abc', '2', '9'); Output = 'bc'; ExitCode = 0 }
        @{ Expression = @('substr', 'abc', '0', '1'); Output = ''; ExitCode = 1 }
        @{ Expression = @('substr', 'abc', '2', 'x'); Output = ''; ExitCode = 1 }
        @{ Expression = @('index', 'hello', 'lo'); Output = '3'; ExitCode = 0 }
        @{ Expression = @('index', 'abc', ''); Output = '0'; ExitCode = 1 }
        @{ Expression = @('+', 'length'); Output = 'length'; ExitCode = 0 }
        @{ Expression = @('+', '+'); Output = '+'; ExitCode = 0 }
        @{ Expression = @('0'); Output = '0'; ExitCode = 1 }
        @{ Expression = @('00'); Output = '00'; ExitCode = 1 }
        @{ Expression = @('-0'); Output = '-0'; ExitCode = 1 }
        @{ Expression = @(''); Output = ''; ExitCode = 1 }
        @{ Expression = @('--', '5'); Output = '5'; ExitCode = 0 }
        @{ Expression = @('1', '|', 'a', '+', '1'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('1', '|', 'a', '*', 'b'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('1', '|', 'a', ':', 'b'); Output = '1'; ExitCode = 0 }
        @{ Expression = @('1', '|', 'match', 'a', 'b'); Output = '1'; ExitCode = 0 }
    ) {
        $r = Invoke-TestGnu expr $Expression
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Be @($Output)
        $r.ExitCode | Should -Be $ExitCode
    }

    It 'reports <Message> for <Expression>' -ForEach @(
        @{ Expression = @('1', '/', '0'); Message = 'division by zero' }
        @{ Expression = @('1', '%', '0'); Message = 'division by zero' }
        @{ Expression = @('1', '/', '0', '|', '1'); Message = 'division by zero' }
        @{ Expression = @('a', '+', '1'); Message = 'non-integer argument' }
        @{ Expression = @('1', '+'); Message = "syntax error: missing argument after '+'" }
        @{ Expression = @('1', '2'); Message = "syntax error: unexpected argument '2'" }
        @{ Expression = @('length'); Message = "syntax error: missing argument after 'length'" }
        @{ Expression = @('match'); Message = "syntax error: missing argument after 'match'" }
        @{ Expression = @('(', '1'); Message = "syntax error: expecting ')' after '1'" }
        @{ Expression = @('(', '1', '2'); Message = "syntax error: expecting ')' instead of '2'" }
        @{ Expression = @('1', ')'); Message = "syntax error: unexpected argument ')'" }
        @{ Expression = @(')'); Message = "syntax error: unexpected ')'" }
        @{ Expression = @('--', '--', '5'); Message = "syntax error: unexpected argument '5'" }
        @{ Expression = @('a', ':', 'a\('); Message = 'Unmatched ( or \(' }
        @{ Expression = @('a', ':', 'a\)'); Message = 'Unmatched ) or \)' }
        @{ Expression = @('a', ':', '['); Message = 'Unmatched [' }
    ) {
        $r = Invoke-TestGnu expr $Expression
        $r.ErrorText | Should -Match ([regex]::Escape($Message))
        $r.Output | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 2
    }

    It 'needs an expression' {
        $r = Invoke-TestGnu expr
        $r.ErrorText | Should -Match 'missing operand'
        $r.ExitCode | Should -Be 2
    }

    It 'does not hide unexpected errors' {
        Mock -ModuleName PSGnuUtils Invoke-GnuExprOr { throw 'boom' }
        { Invoke-GnuExpr 1 } | Should -Throw 'boom'
    }
}
