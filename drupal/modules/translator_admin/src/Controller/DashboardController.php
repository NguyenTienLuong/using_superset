<?php

namespace Drupal\translator_admin\Controller;

use Drupal\Core\Controller\ControllerBase;

class DashboardController extends ControllerBase {

  public function dashboard() {
    // URL public dashboard Superset (dùng slug)
    $superset_url = 'http://localhost:8088/superset/dashboard/drupal/?standalone=true';

    return [
      '#type' => 'inline_template',
      '#template' => '<iframe src="{{ url }}" width="100%" height="1000px" frameborder="0"></iframe>',
      '#context' => ['url' => $superset_url],
    ];
  }

}