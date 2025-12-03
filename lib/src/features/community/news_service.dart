import 'news_model.dart';

class NewsService {
  // Mock data for EV news from India
  Future<List<NewsArticle>> getNews({
    String? category,
    bool featuredOnly = false,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final allNews = _getMockNews();

    // Filter by category if specified
    var filtered = category != null
        ? allNews.where((news) => news.category == category).toList()
        : allNews;

    // Filter by featured if specified
    if (featuredOnly) {
      filtered = filtered.where((news) => news.isFeatured).toList();
    }

    return filtered;
  }

  List<NewsArticle> _getMockNews() {
    final now = DateTime.now();

    return [
      NewsArticle(
        id: '1',
        title: 'Tata Motors Launches Nexon EV Max with 450km Range',
        summary: 'Tata Motors has unveiled the Nexon EV Max, featuring a larger battery pack that delivers an impressive 450km range on a single charge. The new variant is priced competitively at ₹18.5 lakhs.',
        sourceUrl: 'https://evyatra.com/tata-nexon-ev-max-launch',
        sourceName: 'EV Yatra',
        publishedAt: now.subtract(const Duration(hours: 6)),
        imageUrl: 'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=800',
        category: 'vehicles',
        isFeatured: true,
      ),
      NewsArticle(
        id: '2',
        title: 'Delhi Announces 100% Road Tax Waiver for Electric Vehicles',
        summary: 'The Delhi government has announced a complete waiver of road tax for all electric vehicles registered in the capital. This move is expected to boost EV adoption significantly.',
        sourceUrl: 'https://evyatra.com/delhi-ev-tax-waiver',
        sourceName: 'Auto News India',
        publishedAt: now.subtract(const Duration(hours: 12)),
        imageUrl: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=800',
        category: 'policy',
        isFeatured: true,
      ),
      NewsArticle(
        id: '3',
        title: 'Ather Energy Opens 100 Fast Charging Stations Across India',
        summary: 'Ather Energy has expanded its Ather Grid network to 100 fast charging stations across major Indian cities. The company plans to add 200 more stations by end of 2025.',
        sourceUrl: 'https://evyatra.com/ather-charging-expansion',
        sourceName: 'EV Times',
        publishedAt: now.subtract(const Duration(hours: 18)),
        imageUrl: 'https://images.unsplash.com/photo-1593941707874-ef25b8b4a92b?w=800',
        category: 'charging',
      ),
      NewsArticle(
        id: '4',
        title: 'Mahindra XUV400 Electric SUV Bookings Cross 10,000 Mark',
        summary: 'Mahindra\'s electric SUV, the XUV400, has received overwhelming response with bookings crossing 10,000 units within the first month of launch. Deliveries are expected to begin next quarter.',
        sourceUrl: 'https://evyatra.com/mahindra-xuv400-bookings',
        sourceName: 'Car India',
        publishedAt: now.subtract(const Duration(days: 1)),
        imageUrl: 'https://images.unsplash.com/photo-1552519507-da3b142c6e3d?w=800',
        category: 'vehicles',
      ),
      NewsArticle(
        id: '5',
        title: 'FAME II Subsidy Extended Till March 2026',
        summary: 'The central government has extended the FAME II scheme till March 2026, providing continued support for electric vehicle adoption. The subsidy amount remains unchanged at ₹1.5 lakh for electric cars.',
        sourceUrl: 'https://evyatra.com/fame-ii-extension',
        sourceName: 'Economic Times Auto',
        publishedAt: now.subtract(const Duration(days: 1, hours: 6)),
        imageUrl: 'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=800',
        category: 'policy',
      ),
      NewsArticle(
        id: '6',
        title: 'BYD India Plans ₹2,500 Crore Investment in EV Manufacturing',
        summary: 'Chinese EV giant BYD has announced plans to invest ₹2,500 crore in setting up a manufacturing facility in India. The plant will produce electric cars and batteries for the Indian market.',
        sourceUrl: 'https://evyatra.com/byd-india-investment',
        sourceName: 'Business Standard',
        publishedAt: now.subtract(const Duration(days: 2)),
        imageUrl: 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800',
        category: 'industry',
      ),
      NewsArticle(
        id: '7',
        title: 'Ola Electric Scooter Sales Cross 1 Lakh Units',
        summary: 'Ola Electric has achieved a major milestone with cumulative sales of its electric scooters crossing 1 lakh units. The company is now the largest electric two-wheeler manufacturer in India.',
        sourceUrl: 'https://evyatra.com/ola-sales-milestone',
        sourceName: 'Bike India',
        publishedAt: now.subtract(const Duration(days: 2, hours: 12)),
        imageUrl: 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800',
        category: 'industry',
      ),
      NewsArticle(
        id: '8',
        title: 'New Battery Swapping Policy Approved by Government',
        summary: 'The government has approved a comprehensive battery swapping policy aimed at promoting electric mobility. The policy includes standards for interoperable batteries and charging infrastructure.',
        sourceUrl: 'https://evyatra.com/battery-swapping-policy',
        sourceName: 'The Hindu',
        publishedAt: now.subtract(const Duration(days: 3)),
        imageUrl: 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800',
        category: 'policy',
      ),
    ];
  }
}
