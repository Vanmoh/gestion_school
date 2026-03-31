from rest_framework.pagination import PageNumberPagination


class StandardResultsSetPagination(PageNumberPagination):
    """Balanced pagination for heavy list endpoints."""

    page_size = 100
    page_size_query_param = "page_size"
    max_page_size = 500


class AuditLogPagination(PageNumberPagination):
    """Slightly smaller pages for logs to keep filters responsive."""

    page_size = 60
    page_size_query_param = "page_size"
    max_page_size = 300
