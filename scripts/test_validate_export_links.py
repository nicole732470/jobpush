from validate_export_links import page_has_title, rejection_reason


def test_rejection_reason():
    assert rejection_reason(404, "https://example.com/job") == "http_404"
    assert rejection_reason(200, "https://example.com/jobs?error=true") == "error_redirect"
    assert rejection_reason(403, "https://example.com/job") == ""
    assert rejection_reason(200, "https://example.com/job") == ""


def test_page_has_title():
    assert page_has_title(b"<h1>Product Manager, Growth</h1>", "Product Manager, Growth")
    assert not page_has_title(b"<h1>All open roles</h1>", "Product Manager, Growth")
