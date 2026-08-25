import Foundation

/// Checks a server URL and token *before* anything is saved.
///
/// It builds a throwaway `APIClient` from the values passed in rather than reading
/// `env.dataSource`. That is the whole point: Settings used to commit the fields and
/// then immediately read the live data source, which was rebuilt on a 150 ms debounce —
/// so "Test connection" reported on the **previous** server with the **previous** token.
/// A green tick that means nothing is worse than no tick.
///
/// It also asks a question nothing used to ask: *is this actually a Sharp Edge server?*
/// Pointing the app at any random HTTP host previously succeeded here — `/healthz`
/// failing was the only signal — and then produced a decoding error deep inside a screen.
enum ServerProbe {

    enum Result: Equatable {
        /// Reachable and speaking the right protocol. `recipeCount` is what it returned.
        case ok(recipeCount: Int, token: TokenState)
        case unreachable(String)
        /// Answered, but not with a recipe list — wrong host, or a captive portal.
        case notSharpEdge
    }

    enum TokenState: Equatable {
        /// No token given. Reads work; saving will not.
        case none
        case accepted
        case rejected
    }

    static func check(url: URL, token: String) async -> Result {
        let client = APIClient(base: url, tokenProvider: { token.isEmpty ? nil : token })

        // 1. Reachable at all?
        do {
            guard try await client.health() else { return .unreachable("No response") }
        } catch {
            return .unreachable((error as? APIError)?.errorDescription ?? "Unreachable")
        }

        // 2. Is it a Sharp Edge server? A recipe list that decodes is the cheapest proof.
        let count: Int
        do {
            count = try await client.listRecipes().count
        } catch let error as APIError {
            if case .decoding = error { return .notSharpEdge }
            return .unreachable(error.errorDescription ?? "Unreachable")
        } catch {
            return .notSharpEdge
        }

        // 3. Does the token actually let us write? /healthz needs none, so a green tick
        //    from it says nothing about whether saving will work — which is exactly the
        //    failure people hit.
        guard !token.isEmpty else { return .ok(recipeCount: count, token: .none) }
        do {
            // Clearing *checked* shopping items when nothing is checked is authenticated
            // and changes nothing. Deliberately not a write that could lose data.
            try await client.clearShopping(checkedOnly: true)
            return .ok(recipeCount: count, token: .accepted)
        } catch let error as APIError where error == .unauthorized {
            return .ok(recipeCount: count, token: .rejected)
        } catch {
            // Reachable and speaking the protocol; the token is not the thing that failed.
            return .ok(recipeCount: count, token: .accepted)
        }
    }
}
