import XCTest
@testable import LinksMae

final class LinkExtractorTests: XCTestCase {
    func testExtractEntriesFromMixedTextPreservesTitles() {
        let input = """
Conteúdos do curso de Técnico em Análise do Comportamento Aplicada da
ABA Liberta

Módulo 1 - O que é ABA?
1. Introdução https://www.youtube.com/watch?v=mCC0_8eMUKw
2. O que é ABA? https://www.youtube.com/watch?v=uf8Ip45cqqQ
3. Práticas baseadas em evidência https://www.youtube.com/watch?v=E376uIdS1Q8
4. Evidências de eficácia da ABA https://www.youtube.com/watch?v=VpbnCuNzJ3U
5. Direito a uma intervenção comportamental eficaz https://www.youtube.com/watch?v=-Vq_sD79mD8
6. 7 características fundamentais da ABA https://www.youtube.com/watch?v=Z57TtU336Io
7. Agências certificadoras de profissionais que trabalham com ABA https://www.youtube.com/watch?v=S07UgxcY194
8. Princípios gerais das ciências e que incluem a ABA https://www.youtube.com/watch?v=YMlyTn95A38
9. O que NÃO é ABA https://www.youtube.com/watch?v=wHtmcFnrS7A

Módulo 2 - Transtorno no Espectro Autista
1. Introdução - https://www.youtube.com/watch?v=v5Y0wR7PaUo
2. Definição do TEA e características - https://www.youtube.com/watch?v=EjC4d87TP4E
3. Autismo como um transtorno mental - https://www.youtube.com/watch?v=S22sfRY3ey0
4. Mudanças recentes nas classificações - https://www.youtube.com/watch?v=ma1ZUflddhE
5. Características do TEA - https://www.youtube.com/watch?v=we4JreQF4V4
6. Diagnóstico do TEA - https://www.youtube.com/watch?v=G5HI2pMBSeM
7. Outras características comuns de pessoas com TEA - https://www.youtube.com/watch?v=I6BCQSHPqE0
8. Dados sobre prevalência - https://www.youtube.com/watch?v=yMArACoHpOE
9. Marcos do desenvolvimento infantil - https://www.youtube.com/watch?v=J_DSWb2HRrM
10. Sinais precoces/alertas de TEA - https://www.youtube.com/watch?v=DvfK8qFblXE
11. Fatores de risco para TEA - https://www.youtube.com/watch?v=VMlUz_1g_v0
12. Outros transtornos e condições associadas - https://setec.ufmt.br/ava/extensao-ufmt/mod/hvp/view.php?id=3915
"""

        let entries = LinkExtractor.extractEntries(from: input)

        XCTAssertEqual(entries.count, 21)
        XCTAssertEqual(entries.first?.title, "Introdução")
        XCTAssertEqual(entries.first?.url.absoluteString, "https://www.youtube.com/watch?v=mCC0_8eMUKw")
        XCTAssertEqual(entries[1].title, "O que é ABA?")
        XCTAssertEqual(entries[8].title, "O que NÃO é ABA")
        XCTAssertEqual(entries[9].title, "Introdução")
        XCTAssertEqual(entries[9].url.absoluteString, "https://www.youtube.com/watch?v=v5Y0wR7PaUo")
        XCTAssertEqual(entries.last?.title, "Outros transtornos e condições associadas")
        XCTAssertEqual(entries.last?.url.absoluteString, "https://setec.ufmt.br/ava/extensao-ufmt/mod/hvp/view.php?id=3915")
    }
}
