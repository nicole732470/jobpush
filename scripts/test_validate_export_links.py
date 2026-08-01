from validate_export_links import page_has_title_and_id, rejection_reason


def test_rejection_reason():
    assert rejection_reason(404, "https://example.com/job") == "http_404"
    assert rejection_reason(200, "https://example.com/jobs?error=true") == "error_redirect"
    assert rejection_reason(403, "https://example.com/job") == ""
    assert rejection_reason(200, "https://example.com/job") == ""


def test_page_has_title_and_id():
    assert page_has_title_and_id(b"<h1>Product Manager, Growth</h1> id=123", "Product Manager, Growth", "123", "https://example.com/123")
    assert not page_has_title_and_id(b"<h1>Product Manager, Growth</h1>", "Product Manager, Growth", "123", "https://example.com/jobs")
